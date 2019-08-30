$pkg_name="chef-infra-client"
$pkg_origin="chef"
$pkg_version=(Get-Content $PLAN_CONTEXT/../VERSION)
$pkg_upstream_url="https://github.com/chef/chef"
$pkg_revision="1"
$pkg_maintainer="The Chef Maintainers <humans@chef.io>"
$pkg_license=@("Apache-2.0")
$pkg_bin_dirs=@("bin")
$pkg_deps=@(
  "core/openssl"
  "core/cacerts"
  "core/zlib"
  "robbkidd/ruby-plus-devkit/2.6.3"
  #"robbkidd/ruby/2.6.4" # for experimenting with alternatively-built Ruby DELETE BEFORE MERGE
)

$project_root= (Resolve-Path "$PLAN_CONTEXT/../").Path

function Invoke-SetupEnvironment {
    Push-RuntimeEnv -IsPath GEM_PATH "$pkg_prefix/vendor"

    Set-RuntimeEnv -IsPath SSL_CERT_FILE "$(Get-HabPackagePath cacerts)/ssl/cert.pem"
    Set-RuntimeEnv LANG "en_US.UTF-8"
    Set-RuntimeEnv LC_CTYPE "en_US.UTF-8"
}

function Invoke-Build {
    Write-BuildLine "** Ensure a cache directory exists in build directory"
    New-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/vendor/cache" -ItemType Directory -Force | Out-Null

    Write-BuildLine "** Copying project Gemfiles to build directory"
    Get-ChildItem $project_root/Gemfile* | Copy-Item -Destination "$HAB_CACHE_SRC_PATH/$pkg_dirname/"

    Write-BuildLine "** Configuring bundler for this build environment"
    bundle config --local without server docgen maintenance pry travis integration ci chefstyle
    bundle config --local jobs 4

    Install-PathBasedGems
    #Install-GitBasedGems # with a DevKitMSYS2 git on the path, bundler can take care of this. DELETE BEFORE MERGE

    Write-BuildLine " ** With path & git gems in place, bundle package the rest of the gem dependencies"
    $env:GEM_HOME = "$HAB_CACHE_SRC_PATH/$pkg_dirname/"
    bundle install
}

function Invoke-Install {
    Write-BuildLine "** Copy built & cached gems to install directory"
    # Lift the cached gems over to the install directory
    Copy-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/*" -Destination $pkg_prefix -Recurse -Force

    try {
        Push-Location $pkg_prefix
        $env:GEM_HOME = $pkg_prefix
        
        foreach($gem in ("chef-bin", "chef", "ohai")) {
            Invoke-Expression -Command "bundle exec appbundler $project_root $pkg_prefix/bin $gem"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-After {
    # Cleanup some files that are no longer necessary before packaging
    Get-ChildItem $pkg_prefix/vendor/gems -Filter "spec" -Recurse | Remove-Item -Recurse -Force
    Get-ChildItem $pkg_prefix/vendor/cache -Recurse | Remove-Item -Recurse -Force
}

function Install-PathBasedGems {
    # This function exists to copy gems that come from a local path source. Given a collection
    # of path-based gems, it `gem build`s and then unpacks each gem to the source cache build directory.
    # The effect of this is to package only the files that the gemspec defines as part of the "shippable"
    # gem, thus avoiding shipping extraneous files from the source repository.
    Write-BuildLine "** Installing path-based gem dependencies to build directory"
    foreach($pathref in (Get-PathGemRefs)) {
        if ($pathref.path -eq ".") {
            $local_gem_source_path = $project_root
            $gem_name = if ($pathref.platform -eq "ruby") {
                            "chef"
                        } else {
                            "chef-" + $pathref.platform
                        }
        } else {
            $local_gem_source_path = "$project_root/{0}" -f $pathref.name
            $gem_name = $pathref.name
        }
        
        try {
            Push-Location $local_gem_source_path
            Write-BuildLine(" -- Building: {0}" -f $gem_name)
            Invoke-Expression -Command ("gem build $gem_name.gemspec")
            Write-BuildLine(" -- Caching: {0}" -f $gem_name)
            $gems = Get-ChildItem "$gem_name*.gem" 
            foreach($gem in $gems){
                Invoke-Expression -Command ("gem unpack {0} --target {1}" -f $gem.name, "$HAB_CACHE_SRC_PATH/$pkg_dirname/")
                Move-Item $gem -Destination "$HAB_CACHE_SRC_PATH/$pkg_dirname/vendor/cache"
            }
        } finally {
            Pop-Location
        }
    }
}

function Install-GitBasedGems {
    # This function exists because bundler shells out to git to retrieve gems that have been given a git source and
    # the core/git package currently cannot perform all the git commands because (1) sometimes git itself shells out
    # to bash.exe to do a thing and (2) the repackaging of Git-on-Windows does not use PATH but instead attempts to
    # use the directory prefix it was given at build time to find other executables.
    # The workaround applied below uses the git in PATH to manually retrieve those references specified in the Gemfile.lock
    # and overrides bundler to use the folder paths directly to resolve the named components, allowing bundle package to resolve
    # all the required packages. This basically mimics what bundler does for each git source: clone the repo, checkout the revision.
    Write-BuildLine "** Simulating bundler caching git-based gem dependencies"
    foreach($gitref in (Get-GitGemRefs)) {
        try {
            Write-BuildLine(" -- Cloning Gem: {0}" -f $gitref.name)
            New-Item -Path $gitref.cache_path -ItemType Directory | Out-Null
            git clone --bare --no-hardlinks $gitref.uri $gitref.cache_path
            Push-Location $gitref.cache_path
            git fetch --force --tags $gitref.uri "refs/heads/*:refs/heads/*" $gitref.revision
            git clone --no-checkout $gitref.uri $gitref.install_path
            Push-Location $gitref.install_path
            git reset --hard $gitref.revision
        } finally {
            Pop-Location
            Pop-Location
            Write-BuildLine " -- Set local override for the path to the git-ref'd gem so bundler does not attempt to retrieve it"
            Invoke-Expression -Command ("bundle config --local local.{0} {1}" -f @($gitref.name, $gitref.install_path))
        }
    }
}

function Get-PathGemRefs {
    # gnarly parse of the Gemfile.lock to return a collection of gems that are sourced from local paths
    #
    # Example return:
    #   path        name        platform
    #   ----        ----        --------
    #   .           chef        ruby
    #   .           chef        universal-mingw32
    #   chef-bin    chef-bin    ruby
    #   chef-config chef-config ruby

    (ruby -rbundler -rjson -e "puts Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)).specs.select{|spec|spec.source.class == Bundler::Source::Path}.map{|ref| ref.source.options.merge(name: ref.source.name, platform: ref.platform.to_s)}.to_json") | ConvertFrom-Json
}

function Get-GitGemRefs {
    # gnarly parse of the Gemfile.lock to return a collection of gems that are sourced from git repositories
    # and where bundler would cache and install them
    #
    # Example return:
    #   revision     : 56f2187784bf8b6840efc73adb2e35ef5f3862a7
    #   branch       : master
    #   uri          : https://github.com/chef/chefstyle.git
    #   name         : chefstyle
    #   install_path : C:/hab/pkgs/chef/chef-infra-client/15.2.24/20190830182241/bundler/gems/chefstyle-56f2187784bf
    #   cache_path   : C:/hab/pkgs/chef/chef-infra-client/15.2.24/20190830182241/cache/bundler/git/chefstyle-773ac28e9cde9cc5b72913174ac8b2ea4cb68caa   

    (ruby -rbundler -rjson -e "puts Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile)).sources.select{|s|s.is_a? Bundler::Source::Git}.map{|s|s.options.merge(name: s.name, install_path: s.install_path.to_s, cache_path: s.cache_path.to_s)}.to_json") | ConvertFrom-Json
}
$pkg_name="chef-infra-client"
$pkg_origin="chef"
$pkg_version=(Get-Content $PLAN_CONTEXT/../VERSION)
$pkg_upstream_url="https://github.com/chef/chef"
$pkg_revision="1"
$pkg_maintainer="The Chef Maintainers <humans@chef.io>"
$pkg_license=@("Apache-2.0")
$pkg_bin_dirs=@("bin")
$pkg_deps=@(
  "core/cacerts"
  "robbkidd/ruby-plus-devkit/2.6.3"
)

$project_root= (Resolve-Path "$PLAN_CONTEXT/../").Path

function Invoke-SetupEnvironment {
    Push-RuntimeEnv -IsPath GEM_PATH "$pkg_prefix/vendor"

    Set-RuntimeEnv APPBUNDLER_ALLOW_RVM "true" # prevent appbundler from clearing out the carefully constructed runtime GEM_PATH
    Set-RuntimeEnv -IsPath SSL_CERT_FILE "$(Get-HabPackagePath cacerts)/ssl/cert.pem"
    Set-RuntimeEnv LANG "en_US.UTF-8"
    Set-RuntimeEnv LC_CTYPE "en_US.UTF-8"
}

function Invoke-Build {
    try {
        Push-Location $project_root
        $env:GEM_HOME = "$HAB_CACHE_SRC_PATH/$pkg_dirname/vendor"

        Write-BuildLine " ** Configuring bundler for this build environment"
        bundle config --local without server docgen maintenance pry travis integration ci chefstyle
        bundle config --local jobs 4

        Write-BuildLine " ** Using bundler to retrieve the Ruby dependencies"
        bundle install
        Write-BuildLine " ** Running the chef project's 'rake install' to install the path-based gems so they look like any other installed gem."
        bundle exec rake install # this needs to be 'bundle exec'd because a Rakefile makes reference to Bundler
        Write-BuildLine " ** Also 'rake install' any gem sourced as a git reference."
        foreach($git_gem in (Get-ChildItem "$env:GEM_HOME/bundler/gems")) {
            try {
                Push-Location $git_gem
                Write-BuildLine " -- and $git_gem too"
                rake install # this needs to NOT be 'bundle exec'd else bundler complains about dev deps not being installed
            } finally {
                Pop-Location
            }
        }
    } finally {
        Pop-Location
    }
}

function Invoke-Install {
    Write-BuildLine "** Copy built & cached gems to install directory"
    Copy-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/*" -Destination $pkg_prefix -Recurse -Force

    try {
        Push-Location $pkg_prefix
        bundle config --local gemfile $project_root/Gemfile
        foreach($gem in ("chef-bin", "chef", "ohai")) {
            Write-BuildLine "** generating binstubs for $gem with precise version pins"
            Invoke-Expression -Command "vendor/bin/appbundler.bat $project_root $pkg_prefix/bin $gem"
        }
    } finally {
        Pop-Location
        # forget about the build bundle config
        Remove-Item $pkg_prefix/.bundle -Recurse -Force
    }
}

function Invoke-After {
    # Trim the fat before packaging

    # We don't need the cache of downloaded .gem files ...
    Remove-Item $pkg_prefix/vendor/cache -Recurse -Force
    # ... or bundler's cache of git-ref'd gems
    Remove-Item $pkg_prefix/vendor/bundler -Recurse -Force

    # We don't need the gem docs.
    Remove-Item $pkg_prefix/vendor/docs -Recurse -Force
    # We don't need to ship the test suites for every gem dependency.
    Get-ChildItem $pkg_prefix/vendor/gems -Filter "spec" -Directory -Recurse -Depth 1 | Remove-Item -Recurse -Force
}

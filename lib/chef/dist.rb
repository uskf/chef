class Chef
  class Dist
    # This class is not fully implemented, depending on it is not recommended!
    # When referencing a product directly, like Chef (Now Chef Infra)
    PRODUCT = "Beaver Infra Client".freeze

    # The name of the server product
    SERVER_PRODUCT = "Beaver Infra Server".freeze

    # The client's alias (chef-client)
    CLIENT = "beaver-client".freeze

    # name of the automate product
    AUTOMATE = "Beaver Automate".freeze

    # The chef executable, as in `chef gem install` or `chef generate cookbook`
    EXEC = "beaver".freeze

    # product website address
    WEBSITE = "https://chef.io".freeze

    # Chef-Zero's product name
    ZERO = "Beaver Infra Zero".freeze

    # Chef-Solo's product name
    SOLO = "Beaver Infra Solo".freeze

    # The chef-zero executable (local mode)
    ZEROEXEC = "beaver-zero".freeze

    # The chef-solo executable (legacy local mode)
    SOLOEXEC = "beaver-solo".freeze

    # The chef-shell executable
    SHELL = "beaver-shell".freeze

    # Configuration related constants
    # The chef-shell configuration file
    SHELL_CONF = "beaver_shell.rb".freeze

    # The configuration directory
    CONF_DIR = "/etc/#{Chef::Dist::EXEC}".freeze

    # The user's configuration directory
    USER_CONF_DIR = ".beaver".freeze

    # The server's configuration directory
    SERVER_CONF_DIR = "/etc/beaver-server".freeze
  end
end

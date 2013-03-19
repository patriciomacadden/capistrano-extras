require 'capistrano/extras/version'
require 'capistrano/transfer'

module Capistrano
  module Extras
    def self.extended(configuration)
      configuration.load do
        namespace :db do
          desc 'Setup the database'
          task :setup, except: { no_release: true } do
            default_template = <<-EOF
production:
  adapter: mysql2
  encoding: utf8
  reconnect: false
  database: #{Capistrano::CLI.ui.ask("Enter MySQL database name: ")}
  pool: 5
  username: #{Capistrano::CLI.ui.ask("Enter MySQL database username: ")}
  password: #{Capistrano::CLI.ui.ask("Enter MySQL database password: ")}
  host: #{Capistrano::CLI.ui.ask("Enter MySQL database host: ")}
            EOF

            location = fetch(:template_dir, 'config/deploy/config/database.yml.erb')
            template = File.file?(location) ? File.read(location) : default_template

            config = ERB.new(template)

            run "mkdir -p #{shared_path}/config"
            put config.result(binding), "#{shared_path}/config/database.yml"
          end

          desc 'Symlinks database.yml'
          task :symlink, except: { no_release: true } do
            run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
          end

          after 'deploy:setup', 'db:setup' unless fetch(:skip_db_setup, false)
          after 'deploy:finalize_update', 'db:symlink'
        end
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Extras)
end

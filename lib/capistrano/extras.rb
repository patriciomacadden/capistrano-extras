require 'capistrano/extras/version'
require 'capistrano/transfer'
require 'fileutils'

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
            run "mkdir -p #{shared_path}/db"
            put config.result(binding), "#{shared_path}/config/database.yml"
          end

          desc 'Symlinks database.yml'
          task :symlink, except: { no_release: true } do
            run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
          end

          after 'deploy:setup', 'db:setup' unless fetch(:skip_db_setup, false)
          after 'deploy:finalize_update', 'db:symlink'

          def load_database_config(data, environment = 'production')
            config = YAML::load(data)

            {
              database: config[environment]['database'],
              username: config[environment]['username'],
              password: config[environment]['password'],
              host:     config[environment]['host']
            }
          end

          def generate_sql_command(cmd_type, config)
            cmd_conf = {
              'create' => "mysqladmin -u #{config[:username]} --password='#{config[:password]}' create",
              'dump'   => "mysqldump -u #{config[:username]} --password='#{config[:password]}'",
              'drop'   => "mysqladmin -f -u #{config[:username]} --password='#{config[:password]}' drop",
              'import' => "mysql -u #{config[:username]} --password='#{config[:password]}'"
            }

            cmd = cmd_conf[cmd_type]
            cmd += " --host=#{config[:host]}" if config[:host]
            cmd += " --port=#{config[:port]}" if config[:port]
            cmd += " #{config[:database]}"
          end

          namespace :dump do
            desc 'Dump remote database'
            task :remote, roles: :db, only: { primary: true } do
              filename  = "#{application}.remote.#{Time.now.strftime("%Y%m%d%H%M%S")}.sql.gz"
              file      = "#{shared_path}/db/#{filename}"
              config    = ""

              run "#{try_sudo} cat #{shared_path}/config/database.yml" do |ch, st, data|
                config = load_database_config data
              end

              sql_dump_cmd = generate_sql_command('dump', config)
              # log the command with a masked password
              logger.debug sql_dump_cmd.gsub(/(--password=)([^ ]+)/, '\1\'********\'')
              saved_log_level = logger.level
              logger.level = Capistrano::Logger::IMPORTANT

              try_sudo "#{sql_dump_cmd} | gzip -c > #{file}"
              logger.level = saved_log_level

              FileUtils.mkdir_p('tmp/backups')
              get file, "tmp/backups/#{filename}"
              begin
                FileUtils.ln_sf(filename, "tmp/backups/#{application}.remote.latest.sql.gz")
              rescue Exception
                # fallback for file systems that don't support symlinks
                FileUtils.cp_r("tmp/backups/#{filename}", "tmp/backups/#{application}.remote.latest.sql.gz")
              end
              run "#{try_sudo} rm #{file}"
            end

            desc 'Dump local database'
            task :local do
              filename  = "#{application}.local.#{Time.now.strftime("%Y%m%d%H%M%S")}.sql.gz"
              tmpfile   = "tmp/backups/local_dump_tmp.sql"
              file      = "tmp/backups/#{filename}"
              config    = load_database_config IO.read('config/database.yml'), 'development'

              FileUtils::mkdir_p('tmp/backups')

              sql_dump_cmd = generate_sql_command('dump', config)
              run_locally "#{sql_dump_cmd} > #{tmpfile}"

              File.open(tmpfile, 'r+') do |f|
                gz = Zlib::GzipWriter.open(file)
                while (line = f.gets)
                  gz << line
                end
                gz.flush
                gz.close
              end

              begin
                FileUtils.ln_sf(filename, "tmp/backups/#{application}.local.latest.sql.gz")
              rescue Exception
                # fallback for file systems that don't support symlinks
                FileUtils.cp_r("tmp/backups/#{filename}", "tmp/backups/#{application}.local.latest.sql.gz")
              end
              FileUtils.rm(tmpfile)
            end
          end
          
          desc "Dump remote database, download it to local & populate here"
          task :import, roles: :db, only: { primary: true } do
            db.dump.remote

            begin
              # gunzip does not work with a symlink
              zipped_file_path = `readlink tmp/backups/#{application}.remote.latest.sql.gz`.chop
              zipped_file_path = "tmp/backups/#{zipped_file_path}"
            rescue Exception
              # fallback for file systems that don't support symlinks
              zipped_file_path = "tmp/backups/#{application}.remote.latest.sql.gz"
            end
            unzipped_file_path = "tmp/backups/#{application}_dump.sql"

            run_locally "gunzip -c #{zipped_file_path} > #{unzipped_file_path}"

            config = load_database_config IO.read('config/database.yml'), 'development'

            run_locally generate_sql_command('drop', config)
            run_locally generate_sql_command('create', config)

            sql_import_cmd = generate_sql_command('import', config)
            run_locally "#{sql_import_cmd} < #{unzipped_file_path}"

            FileUtils.rm("#{unzipped_file_path}")
          end

          desc "Dump local database, load it to remote & populate there"
          task :export, roles: :db, only: { primary: true } do
            filename  = "#{application}.local.latest.sql.gz"
            file      = "tmp/backups/#{filename}"
            sqlfile   = "#{application}_dump.sql"
            config    = ""

            db.dump.local

            upload(file, "#{shared_path}/db/#{filename}", :via => :scp)
            run "#{try_sudo} gunzip -c #{shared_path}/db/#{filename} > #{shared_path}/db/#{sqlfile}"

            run "#{try_sudo} cat #{shared_path}/config/database.yml" do |ch, st, data|
              config = load_database_config data
            end

            try_sudo generate_sql_command('drop', config)
            try_sudo generate_sql_command('create', config)

            sql_import_cmd = generate_sql_command('import', config)

            try_sudo "#{sql_import_cmd} < #{shared_path}/db/#{sqlfile}"

            run "#{try_sudo} rm #{shared_path}/db/#{filename}"
            run "#{try_sudo} rm #{shared_path}/db/#{sqlfile}"
          end
        end
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Extras)
end

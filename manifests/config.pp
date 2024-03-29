# @summary
#   Configures Icinga Web 2.
#
# @api private
#
class icingaweb2::config {

  $conf_dir             = $::icingaweb2::globals::conf_dir
  $conf_user            = $::icingaweb2::conf_user
  $conf_group           = $::icingaweb2::conf_group

  $logging              = $::icingaweb2::logging
  $logging_file         = $::icingaweb2::logging_file
  $logging_dir          = dirname($::icingaweb2::logging_file)
  $logging_level        = $::icingaweb2::logging_level
  $logging_facility     = $::icingaweb2::logging_facility
  $logging_application  = $::icingaweb2::logging_application
  $show_stacktraces     = $::icingaweb2::show_stacktraces
  $module_path          = $::icingaweb2::module_path

  $theme                = $::icingaweb2::theme
  $theme_disabled       = $::icingaweb2::theme_disabled

  $cookie_path          = $::icingaweb2::cookie_path

  $import_schema        = $::icingaweb2::import_schema
  $mysql_db_schema      = $::icingaweb2::globals::mysql_db_schema
  $pgsql_db_schema      = $::icingaweb2::globals::pgsql_db_schema
  $db_name              = $::icingaweb2::db_name
  $db_host              = $::icingaweb2::db_host
  $db_port              = $::icingaweb2::db_port
  $db_type              = $::icingaweb2::db_type
  $db_username          = $::icingaweb2::db_username
  $db_password          = $::icingaweb2::db_password
  $default_domain       = $::icingaweb2::default_domain
  $admin_role           = $::icingaweb2::admin_role
  $admin_username       = $::icingaweb2::default_admin_username
  $admin_password       = $::icingaweb2::default_admin_password

  $config_backend       = $::icingaweb2::config_backend
  $config_resource      = $::icingaweb2::config_backend ? {
    'ini' => undef,
    'db'  => "${db_type}-icingaweb2",
  }

  File {
    mode  => '0660',
    owner => $conf_user,
    group => $conf_group
  }

  Exec {
    user => 'root',
    path => $::path,
  }

  file { $logging_dir:
    ensure => directory,
    mode   => '0750',
  }
  file { $logging_file:
    ensure => file,
    mode   => '0640',
  }

  icingaweb2::inisection { 'config-logging':
    section_name => 'logging',
    target       => "${conf_dir}/config.ini",
    settings     => {
      'log'         => $logging,
      'file'        => $logging_file,
      'level'       => $logging_level,
      'facility'    => $logging_facility,
      'application' => $logging_application,
    },
  }

  $settings = {
    'show_stacktraces' => $show_stacktraces,
    'module_path'      => $module_path,
    'config_backend'   => $config_backend,
    'config_resource'  => $config_resource,
  }


  icingaweb2::inisection { 'config-global':
    section_name => 'global',
    target       => "${conf_dir}/config.ini",
    settings     => delete_undef_values($settings),
  }

  if $default_domain {
    icingaweb2::inisection { 'config-authentication':
      section_name => 'authentication',
      target       => "${conf_dir}/config.ini",
      settings     => {
        'default_domain' => $default_domain,
      }
    }
  }

  icingaweb2::inisection { 'config-themes':
    section_name => 'themes',
    target       => "${conf_dir}/config.ini",
    settings     => {
      'default'  => $theme,
      'disabled' => $theme_disabled,
    },
  }

  if $cookie_path {
    icingaweb2::inisection {'config-cookie':
      section_name => 'cookie',
      target       => "${conf_dir}/config.ini",
      settings     => {
        'path'     => $cookie_path,
      },
    }
  }

  file { "${conf_dir}/modules":
    ensure => 'directory',
    mode   => '2770',
  }

  file { "${conf_dir}/enabledModules":
    ensure => 'directory',
    mode   => '2770',
  }

  if $import_schema or $config_backend == 'db' {
    icingaweb2::config::resource { "${db_type}-icingaweb2":
      type        => 'db',
      host        => $db_host,
      port        => $db_port,
      db_type     => $db_type,
      db_name     => $db_name,
      db_username => $db_username,
      db_password => $db_password,
    }

    icingaweb2::config::groupbackend { "${db_type}-group":
      backend  => 'db',
      resource => "${db_type}-icingaweb2"
    }

    icingaweb2::config::authmethod { "${db_type}-auth":
      backend  => 'db',
      resource => "${db_type}-icingaweb2"
    }
  }

  if $import_schema {

    if $admin_role {
      icingaweb2::config::role { $admin_role['name']:
        users       => if $admin_role['users'] { join(union([$admin_username], $admin_role['users'])) } else { $admin_username },
        groups      => if $admin_role['groups'] { join($admin_role['groups']) } else { undef },
        permissions => '*',
      }
    }

    case $db_type {
      'mysql': {
        exec { 'import schema':
          command => "mysql -h '${db_host}' -P '${db_port}' -u '${db_username}' -p'${db_password}' '${db_name}' < '${mysql_db_schema}'",
          unless  => "mysql -h '${db_host}' -P '${db_port}' -u '${db_username}' -p'${db_password}' '${db_name}' -Ns -e 'SELECT 1 FROM icingaweb_user'",
          notify  => Exec['create default admin user'],
        }

        exec { 'create default admin user':
          command     => "echo \"INSERT INTO icingaweb_user (name, active, password_hash) VALUES (\\\"${admin_username}\\\", 1, \\\"`php -r 'echo password_hash(\"${admin_password}\", PASSWORD_DEFAULT);'`\\\")\" | mysql -h '${db_host}' -P '${db_port}' -u '${db_username}' -p'${db_password}' '${db_name}' -Ns",
          refreshonly => true,
        }
      }
      'pgsql': {
        exec { 'import schema':
          environment => ["PGPASSWORD=${db_password}"],
          command     => "psql -h '${db_host}' -p '${db_port}' -U '${db_username}' -d '${db_name}' -w -f ${pgsql_db_schema}",
          unless      => "echo \"INSERT INTO icingaweb_user (name, active, password_hash) VALUES (\\\"${admin_username}\\\", 1, \\\"`php -r 'echo password_hash(\"${admin_password}\", PASSWORD_DEFAULT);'`\\\")\" | psql -h '${db_host}' -p '${db_port}' -U '${db_username}' -d '${db_name}' -w",
          notify      => Exec['create default admin user'],
        }

        exec { 'create default admin user':
          environment => ["PGPASSWORD=${db_password}"],
          command     => "psql -h '${db_host}' -p '${db_port}' -U '${db_username}' -d '${db_name}' -w -c \"INSERT INTO icingaweb_user(name, active, password_hash) VALUES ('icingaadmin', 1, '\\\$1\\\$3no6eqZp\\\$FlcHQDdnxGPqKadmfVcCU.')\"",
          refreshonly => true,
        }
      }
      default: {
        fail('The database type you provided is not supported.')
      }
    }
  }
}

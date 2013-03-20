# Capistrano::Extras

Extra tasks for capistrano.

## Installation

Add this line to your application's Gemfile:

```bash
group :development do
  gem 'capistrano-extras'
end
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
$ gem install capistrano-extras
```

## Usage

* Require the gem in Capfile:

```
require 'capistrano/extras'
```

* Run `cap -T` to view the new tasks

## Tasks

* `db:setup`: Asks you about the database configuration. Then it creates the
`database.yml` file in `shared/config/database.yml`

* `db:symlink`: Creates a symlink from the `shared/config/database.yml` to the
current release.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## TODO

* Tests!

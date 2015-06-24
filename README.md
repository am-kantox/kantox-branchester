# Kantox::Branchester

Include this gem into your gemfile and stay notified about all the possible
merge conflicts against all the currently active branches.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kantox-branchester'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kantox-branchester

## Usage

Very first run will be long, since the information about all the active
branches is to be gathered. The subsequent run should not take long since
the results are cached.

All logs are stored in `branchester` directory. The configuration is located
in `config/branchester.yml`. The file will appear after first run.

Typical use case would be to include `bundle exec branchester` into local
`post-commit` hook, or to run it manually. Please note, that once blacklisted,
the branch would not be checked against until explicitly removed from
`config/branchester.yml`.

Typical output:

#### For last 30 days / 1000 commits

```bash
Will try to merge 28 branches:
============================
****************************
============================

Some branches failed to merge automatically into feature/check-branchester
feature/CO-32_CM_sha_dir_eme ==>
  Recorded preimage for 'Gemfile.lock'
	Recorded preimage for 'db/schema.rb'
	CONFLICT (content): Merge conflict in db/schema.rb
	CONFLICT (content): Merge conflict in Gemfile.lock
	CONFLICT (content): Merge conflict in Gemfile
	Automatic merge failed; fix conflicts and then commit the result.

hotfix/PT-2246-demo-platform-phone-quotes ==>
  CONFLICT (content): Merge conflict in app/mutations/liquidity_provider_router.rb
	Automatic merge failed; fix conflicts and then commit the result.

vemv-letter-opener-indication ==>
  CONFLICT (content): Merge conflict in config/environments/development.rb
	Automatic merge failed; fix conflicts and then commit the result.

```

#### For last 7 days / 1000 commits

```bash
Will try to merge 7 branches:
=======
*******
=======

Everything merged successfully into feature/check-branchester
```

## Configuration

```yaml
--- !ruby/hash:Hashie::Mash
config: !ruby/hash:Hashie::Mash
  age: 7
  retro: 1000
```

The above means only branches, not older than 7 days and only last 1000 commits
will be taken into account.

## To Do

  * «urgent» update a list of active branches once on a startup;
  * accept a `--full` parameter in the command line, forcing to ignore blacklist.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/kantox-branchester. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

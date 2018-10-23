# Decaf

Automatically converts [Mocha](https://github.com/freerange/mocha) stubbing and mock syntax to [rspec-mocks](https://github.com/rspec/rspec-mocks) syntax.

Whilst this script covers most cases it's not perfect. PR's welcome!

### Warning: best used with version control! Running this script will overwrite the files!

Run the tests via:

```ruby
bundle exec rspec spec
```

Update your files via:
```
DIRECTORY="/path/to/directory" bundle exec run.rb
```

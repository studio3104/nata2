# Nata2 [![Build Status](https://travis-ci.org/studio3104/nata2.svg)](https://travis-ci.org/studio3104/nata2)



## Usage

#### Install

git clone,

```
$ git clone https://github.com/studio3104/nata2.git
```

and bundle install.

```
$ cd nata2
$ bundle install
```

#### Configurations

describe the setting in `config.toml`.  
specify `dburl` of [Sequel](http://sequel.jeremyevans.net/).

```
dburl = "mysql2://nata:password@localhost/nata2"
```

**strongly recommend using `mysql2`.**  
because do not have enough test in other databases.

#### Initialize database

create `nata2` database.

```
$ mysql -uroot -p -e'CREATE DATABASE `nata2`'
```

create tables.

```
$ bin/nata2server_init_database
```

#### Launch

```
$ rackup
```

## Register a slow query

Post parsed slow query log.

```
http://nata2.server/api/1/:sarvice_name/:host_name/:database_name

{
  datetime: 1390883951,
  user: 'user',
  host: 'localhost',
  query_time: 2.001227,
  lock_time: 0.0,
  rows_sent: 1,
  rows_examined:0,
  sql: 'SELECT SLEEP(2)'
}
```

#### Clients

- [nata2-client](https://github.com/studio3104/nata2-client)
- [fluent-plugin-nata2](https://github.com/studio3104/fluent-plugin-nata2)

## Contributing

1. Fork it ( http://github.com/studio3104/nata2/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

Copyright (c) 2014 studio3104

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Also, [`lib/nata2/mysqldumpslow.rb`](https://github.com/studio3104/nata2/blob/master/lib/nata2/mysqldumpslow.rb) contains the modified [`mysqldumpslow`](http://dev.mysql.com/doc/refman/5.7/en/mysqldumpslow.html), this is GPL2 license applies.**

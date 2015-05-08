# Nata2 [![Build Status](https://travis-ci.org/studio3104/nata2.svg)](https://travis-ci.org/studio3104/nata2)

Nata2 is a tool that can be summarized by integrating the slow query log.  
require **Ruby 2.0 or later**.

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
dburl = "mysql2://YOUR_SPECIFIED_USERNAME:YOUR_SPECIFIED_USER's_PASSWORD@YOUR_MySQL_HOST/nata2"
```

**strongly recommend using `mysql2`.**  
because do not have enough test in other databases.

#### Initialize database

create `nata2` database.

```
$ mysql -uroot -p -e'CREATE DATABASE `nata2`'
```

create schema with [Ridgepole](https://github.com/winebarrel/ridgepole).

```
$ bundle exec ridgepole -c '{ adapter: mysql2, database: nata2, username: YOUR_SPECIFIED_USERNAME, password: YOUR_SPECIFIED_USER's_PASSWORD, host: YOUR_MySQL_HOST }' --apply
```

#### Launch

```
$ bundle exec rackup
```

## Register a slow query

Post parsed slow query log.

```
http://nata2.server/api/1/:service_name/:host_name/:database_name

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

If using curl, you should create post request like this.  
Header needs `Content-Type: application/x-www-form-urlencoded`  (-d use this Content-Type)  
Form Fotmat is `key1=value1&key2=value2...`  

```
curl -d "datetime=1390883951" \
    -d "user=aa" \
    -d "host=localhost" \
    -d "query_time=2.001227" \
    -d "lock_time=0" \
    -d "rows_sent=1" \
    -d "rows_examined=0" \
    -d "sql=SELECTSLEEP(2)" \
    http://nata2.server/api/1/:service_name/:host_name/:database_name
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


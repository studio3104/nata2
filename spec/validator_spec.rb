require 'spec_helper'

describe Nata::Validator do
  context 'String' do
    it 'with single arguments' do
      expect(
        Nata::Validator.validate(
          test: { isa: 'STRING', val: 'test_value' }
        )
      ).to eq(test: 'test_value')
    end

    it 'with one more arguments' do
      expect(
        Nata::Validator.validate(
          test1: { isa: 'STRING', val: 'test_value1' },
          test2: { isa: 'STRING', val: 'test_value2' },
          test3: { isa: 'STRING', val: 'test_value3' },
        )
      ).to eq(
        test1: 'test_value1', test2: 'test_value2', test3: 'test_value3'
      )
    end
  end

  context 'Integer' do
    it 'with single arguments' do
      expect(Nata::Validator.validate(
        test: { isa: 'INT', val: 1 }
      )).to eq(test: 1)
    end

    it 'with one more arguments' do
      expect(Nata::Validator.validate(
        test1: { isa:  'INT', val: 1 },
        test2: { isa:  'INT', val: 2 },
        test3: { isa:  'INT', val: 3 },
      )).to eq(
        test1: 1, test2: 2, test3: 3
      )
    end

    it 'string values' do
      expect(Nata::Validator.validate(
        test1: { isa:  'INT', val: '1' },
        test2: { isa:  'INT', val: '2' },
        test3: { isa:  'INT', val: '3' },
      )).to eq(
        test1: 1, test2: 2, test3: 3
      )
    end
  end

  context 'Float' do
    it 'with single arguments' do
      expect(Nata::Validator.validate(
        test: { isa: 'FLOAT', val: 1.0 }
      )).to eq(
        test: 1.0
      )
    end

    it 'with one more arguments' do
      expect(Nata::Validator.validate(
        test1: { isa: 'FLOAT', val: 1.0 },
        test2: { isa: 'FLOAT', val: 2.0 },
        test3: { isa: 'FLOAT', val: 3.0 },
      )).to eq(
        test1: 1.0, test2: 2.0, test3: 3.0
      )
    end

    it 'string values' do
      expect(Nata::Validator.validate(
        test1: { isa: 'FLOAT', val: '121.134012' },
        test2: { isa: 'FLOAT', val: '2132.031512' },
        test3: { isa: 'FLOAT', val: '214213.9' },
      )).to eq(
        test1: 121.134012, test2: 2132.031512, test3: 214213.9
      )
    end
  end

  context 'datetime' do
    it 'with single arguments' do
      expect(Nata::Validator.validate(
        test: { isa: 'TIME', val: '2013/10/31 12:38:58' }
      )).to eq(
        test: Time.parse('2013-10-31 12:38:58 +0900').to_i
      )
    end

    it 'with one more arguments' do
      expect(Nata::Validator.validate(
        test1: { isa: 'TIME', val: '2100/12/31' },
        test2: { isa: 'TIME', val: '2013-10-31 10:11:12 JST' },
        test3: { isa: 'TIME', val: '11.11.2013 15:14:16 UTC' },
      )).to eq(
        test1: Time.parse('2100-12-31 00:00:00 +0900').to_i,
        test2: Time.parse('2013-10-31 10:11:12 +0900').to_i,
        test3: Time.parse('2013-11-11 15:14:16 UTC').to_i,
      )
    end
  end

  context 'other' do
    it 'blank values' do
      expect(Nata::Validator.validate(
        test1: { isa: 'STRING', val: nil },
        test2: { isa: 'INT', val: nil },
        test3: { isa: 'FLOAT', val: nil },
        test4: { isa: 'TIME', val: nil },
        test5: { isa: 'STRING', val: ' ' },
        test6: { isa: 'INT', val: ' ' },
        test7: { isa: 'FLOAT', val: ' ' },
        test8: { isa: 'TIME', val: ' ' },
      )).to eq(
        test1: nil, test2: nil, test3: nil, test4: nil,
        test5: nil, test6: nil, test7: nil, test8: nil,
      )
    end

    it 'parsed slow query log' do
      expect(Nata::Validator.validate(
        user:          { isa: 'STRING', val: 'root[root]' },
        host:          { isa: 'STRING', val: 'localhost' },
        sql:           { isa: 'STRING', val: 'select sleep(10)' },
        rows_sent:     { isa: 'INT',    val: 1 },
        rows_examined: { isa: 'INT',    val: 0 },
        query_time:    { isa: 'FLOAT',  val: 10.00111 },
        lock_time:     { isa: 'FLOAT',  val: 0.0 },
        date:          { isa: 'TIME',   val: '2013/10/31 12:38:58' },
      )).to eq(
        user: 'root[root]',
        host: 'localhost',
        sql: 'select sleep(10)',
        rows_sent: 1,
        rows_examined: 0,
        query_time: 10.00111,
        lock_time: 0.0,
        date: Time.parse('2013-10-31 12:38:58 +0900').to_i,
      )
    end
  end
end

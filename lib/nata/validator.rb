require 'time'

module Nata
  class DataInvalidError < StandardError; end
  class Validator
    def self.validate(target)
      result = {}
      target.each do |subject, rule|
        if rule[:val].nil? || rule[:val].is_a?(String) && (rule[:val].empty? || rule[:val].match(/^\s+$/))
          result[subject] = nil
          next
        end

        result[subject] = case rule[:isa]
                          when 'TIME'
                            validate_datetime(subject, rule[:val])
                          when 'STRING'
                            validate_common(String, subject, rule[:val])
                          when 'INT'
                            value = prepare_value_to_validate_integer(rule[:val])
                            validate_common(Integer, subject, value)
                          when 'FLOAT'
                            value = prepare_value_to_validate_float(rule[:val])
                            validate_common(Float, subject, value)
                          else
                            raise
                          end

      end
      result
    end

    def self.validate_common(klass, subject, value)
      raise DataInvalidError, "#{subject}[#{value}] is not #{klass.to_s.downcase}" unless value.is_a?(klass)
      validate_available_in_sql(value)
      value
    end

    def self.prepare_value_to_validate_integer(value)
      if value.is_a?(String) && value.match(/^\d+$/)
        value.to_i
      else
        value
      end
    end

    def self.prepare_value_to_validate_float(value)
      if value.is_a?(String) && value.match(/^\d+\.(\d+|\d+e-\d+)$/)
        value.to_f
      else
        value
      end
    end

    def self.validate_datetime(subject, value)
      begin
        Time.parse(value).to_i
      rescue ArgumentError
        raise DataInvalidError, "#{subject} is not datetime"
      end
    end

    def self.validate_available_in_sql(part)
      ## SQL の validation ロジックは STRING とは別に設けたほうがよさそうなのであとで
      #
      # 'SELECT * FROM `hoge`' のような SQL が validation に通るように gsub してる
      # match の正規表現に入れてないのは、スペースだけの連続とかが来たことを想定して
      if !part.to_s.gsub(/(\s+|`|\.|\[|\]|\(|\))/,'').match(/^[0-9a-zA-Z_\-\,\'\"]+$/)
#        raise DataInvalidError, "#{part} is not available in SQL"
      end
    end
  end
end

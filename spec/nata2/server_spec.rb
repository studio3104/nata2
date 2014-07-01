require 'spec_helper'

describe 'Nata Server Controller' do
  let(:service_name) { TestData::ServiceName }
  let(:host_name) { TestData::HostName }
  let(:database_name) { TestData::DatabaseName }

  describe 'APIs' do
    it 'API document' do
      get '/docs/api'
      expect(last_response).to be_ok
    end

    describe 'POST /api/1/:service_name/:host_name/:database_name' do
      let(:post_data) { TestData::ParsedSlowQuery }

      it 'create a new slow query record' do
        post %Q{/api/1/#{service_name}/#{host_name}/#{database_name}}, post_data
        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)['error']).to eq(0)
      end

      it 'create a new slow query record without required params' do
        post_data_without_required_params = post_data.clone
        post_data_without_required_params.delete(:sql)
        post %Q{/api/1/#{service_name}/#{host_name}/#{database_name}}, post_data_without_required_params
        expect(last_response.status).to eq(400)
        expect(JSON.parse(last_response.body, symbolize_names: true)).to eq(error: 1, messages: { sql: 'sql: missing or blank' })
      end
    end
  end

  it 'top page' do
    get '/'
    expect(last_response).to be_ok
  end

  context 'a slow query view' do
    it '200' do
      get '/slow_query/1'
      expect(last_response).to be_ok
    end
    it '404' do
      get '/slow_query/18446744073709551616'
      expect(last_response).to be_not_found
    end
  end

  context 'a dumped slow query view' do
    it '200' do
      get '/dumped_query/eyJjb3VudCI6MiwidXNlciI6WyJ1c2VyIl0sImhvc3QiOlsibG9jYWxob3N0Il0sImF2ZXJhZ2UiOnsicXVlcnlfdGltZSI6Mi4wMDEyMjcsImxvY2tfdGltZSI6MC4wLCJyb3dzX3NlbnQiOjEuMCwicm93c19leGFtaW5lZCI6MC4wfSwic3VtbWF0aW9uIjp7InF1ZXJ5X3RpbWUiOjQuMDAyNDU0LCJsb2NrX3RpbWUiOjAuMCwicm93c19zZW50IjoyLCJyb3dzX2V4YW1pbmVkIjowfSwibm9ybWFyaXplZF9zcWwiOiJzZWxlY3Qgc2xlZXAoTikiLCJyYXdfc3FsIjpudWxsfQ=='
      expect(last_response).to be_ok
    end
    it '404' do
      get '/dumped_query/not_found'
      expect(last_response).to be_not_found
    end
  end

  context 'view per database' do
    it '200' do
      get %Q{/view/#{service_name}/#{host_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/view/NOT_REGISTERED_SERVICE/NOT_REGISTERED_HOST/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end

  context 'complex view per database' do
    it '200' do
      get %Q{/view_complex/#{service_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/view_complex/NOT_REGISTERED_SERVICE/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end

  context 'dump view per database' do
    it '200' do
      get %Q{/dump/#{service_name}/#{host_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/dump/NOT_REGISTERED_SERVICE/NOT_REGISTERED_HOST/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end

  context 'complex dump view per database' do
    it '200' do
      get %Q{/dump_complex/#{service_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/dump_complex/NOT_REGISTERED_SERVICE/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end

  context 'list view per database' do
    it '200' do
      get %Q{/list/#{service_name}/#{host_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/list/NOT_REGISTERED_SERVICE/NOT_REGISTERED_HOST/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end

  context 'complex list view per database' do
    it '200' do
      get %Q{/list_complex/#{service_name}/#{database_name}}
      expect(last_response).to be_ok
    end
    it '404' do
      get %Q{/list_complex/NOT_REGISTERED_SERVICE/NOT_REGISTERED_DATABASE}
      expect(last_response).to be_not_found
    end
  end
end

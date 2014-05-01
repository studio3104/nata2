require 'webmock/rspec'
require 'spec_helper'
require 'nata2/hrforecast'

describe Nata2::HRForecast do
  let(:hf_fqdn) { 'localhost' }
  let(:hf_port) { 10080 }
  let(:base_url) { 'http://' + hf_fqdn + ':' + hf_port.to_s }
  let(:service_name) { 'test_service' }
  let(:section_name) { 'test_host' }
  let(:graph_name) { 'test_database' }
  let(:graph_name2) { 'test_database2' }
  let(:graph_name_does_not_exist) { 'test_database_not_exist' }
  let(:complex_graph_name) { 'test_complex' }
  let(:hf) { Nata2::HRForecast.new(hf_fqdn, hf_port) }

  describe '#update' do
    context 'not specify options' do
      it 'assert response value' do
        response = hf.update(service_name, section_name, graph_name, 1)
        expect(response).to be_a(Hash)

        metrics = response
        expect(metrics[:service_name]).to eq(service_name)
        expect(metrics[:section_name]).to eq(section_name)
        expect(metrics[:graph_name]).to eq(graph_name)
      end
    end

    context 'specify datetime' do
      it 'with valid datetime format' do
        valid_formats = [
          'Wed, 09 Feb 1994 22:23:32 GMT',       # -- HTTP format
          'Thu Feb  3 17:03:55 GMT 1994',        # -- ctime(3) format
          'Thu Feb  3 00:00:00 1994',            # -- ANSI C asctime() format
          'Tuesday, 08-Feb-94 14:15:29 GMT',     # -- old rfc850 HTTP format
          'Tuesday, 08-Feb-1994 14:15:29 GMT',   # -- broken rfc850 HTTP format
          '03/Feb/1994:17:03:55 -0700',          # -- common logfile format
          '09 Feb 1994 22:23:32 GMT',            # -- HTTP format (no weekday)
          '08-Feb-94 14:15:29 GMT',              # -- rfc850 format (no weekday)
          '08-Feb-1994 14:15:29 GMT',            # -- broken rfc850 format (no weekday)
          '1994-02-03 14:15:29 -0100',           # -- ISO 8601 format
          '1994-02-03 14:15:29',                 # -- zone is optional
          '1994-02-03',                          # -- only date
          '1994-02-03T14:15:29',                 # -- Use T as separator
          '19940203T141529Z',                    # -- ISO 8601 compact format
          '19940203',                            # -- only date
        ]
        valid_formats.each do |datetime|
          response = hf.update(service_name, section_name, graph_name, 1, datetime: datetime)
          expect(response).to be_a(Hash)
        end
      end

      it 'with invalid datetime format' do
        hf.delete_graph(service_name, section_name, graph_name)
        expect {
          hf.update(service_name, section_name, graph_name, 1, datetime: 'invalid datetime format')
        }.to raise_error(RuntimeError, %q{["datetime is not null"]})
      end
    end
  end

  describe '#edit_graph' do
    context 'when graph exists' do
      context 'change color' do
        it 'with valid color code' do
          response = hf.edit_graph(service_name, section_name, graph_name, color: '#000000')
          expect(response[:error]).to eq(0)
        end

        it 'with invalid color code' do
          expect {
            hf.edit_graph(service_name, section_name, graph_name, color: 'invalid color code')
          }.to raise_error(RuntimeError, %q{{:color=>"#000000の形式で入力してください"}})
        end
      end

      context 'change sort' do
        it 'with valid sort num' do
          response = hf.edit_graph(service_name, section_name, graph_name, sort: 10)
          expect(response[:error]).to eq(0)
        end

        it 'with invalid sort num' do
          expect {
            hf.edit_graph(service_name, section_name, graph_name, sort: 'invalid sort num')
          }.to raise_error(RuntimeError, %q{{:sort=>"値が正しくありません"}})
        end
      end
    end

    context 'when graph does not exist' do
      it do
        expect {
          hf.edit_graph(service_name, section_name, graph_name_does_not_exist, color: '#000000')
        }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#create_complex_graph' do
    context 'not specify options' do
      it  do
        graph_ids = [graph_name, graph_name2].map { |g| hf.graph_status(service_name, section_name, g)[:id] }
        response = hf.create_complex_graph(service_name, section_name, complex_graph_name, graph_ids)
        expect(response[:error]).to eq(0)
      end
    end

    context 'specify stack' do
      it 'with valid stack num' do
        graph_ids = [graph_name, graph_name2].map { |g| hf.graph_status(service_name, section_name, g)[:id] }
        response = hf.create_complex_graph(service_name, section_name, complex_graph_name, graph_ids, stack: 0)
        expect(response[:error]).to eq(0)
      end

      it 'with invalid stack num' do
        graph_ids = [graph_name, graph_name2].map { |g| hf.graph_status(service_name, section_name, g)[:id] }
        expect {
          hf.create_complex_graph(service_name, section_name, complex_graph_name, graph_ids, stack: 'invalid stack num')
        }.to raise_error(RuntimeError, '{:stack=>"スタックの値が正しくありません"}')
      end
    end

    context 'specify sort' do
    end
  end

  describe '#edit_complex_graph' do
  end

  describe '#delete_graph' do
    context 'delete graph that exist' do
      it do
        response = hf.delete_graph(service_name, section_name, graph_name)
        expect(response[:error]).to eq(0)
      end
    end

    context 'delete graph that does not exist' do
      it do
        expect {
          hf.delete_graph(service_name, section_name, graph_name_does_not_exist)
        }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#delete_complex_graph' do
  end

  describe '#graph_exist?' do
  end

  describe '#complex_graph_exist?' do
  end

  before(:each) do
    stub_request(:post, %Q{#{base_url}/api/#{service_name}/#{section_name}/#{graph_name}}).to_return(body:  %Q{{"error":0,"metricses":[{"colors":["#9966cc"],"updated_at":null,"meta":{"color":"#9966cc"},"created_at":null,"sort":"0","section_name":"#{section_name}","graph_name":"#{graph_name}","service_name":"#{service_name}","id":"1","color":"#9966cc"}]}})
    stub_request(:post, %Q{#{base_url}/api/#{service_name}/#{section_name}/#{graph_name2}}).to_return(body: %Q{{"error":0,"metricses":[{"colors":["#9966cc"],"updated_at":null,"meta":{"color":"#9966cc"},"created_at":null,"sort":"0","section_name":"#{section_name}","graph_name":"#{graph_name}","service_name":"#{service_name}","id":"2","color":"#9966cc"}]}})
    stub_request(:post, %Q{#{base_url}/api/#{service_name}/#{section_name}/#{graph_name}}).
      with(body: {number: '1', datetime: 'invalid datetime format'}).
        to_return(status: 400, body: '{"error":1,"messages":["datetime is not null"]}')
    hf.update(service_name, section_name, graph_name2, 150)
    hf.update(service_name, section_name, graph_name, 100)
  end

  after(:each) do
    if hf.graph_exist?(service_name, section_name, graph_name)
      hf.delete_graph(service_name, section_name, graph_name)
    end
    if hf.complex_graph_exist?(service_name, section_name, complex_graph_name)
      hf.delete_complex_graph(service_name, section_name, complex_graph_name)
    end
  end

  before do
    stub_request(:post, %Q{#{base_url}/delete/#{service_name}/#{section_name}/#{graph_name}}).to_return(body: '{"error":0}')
    stub_request(:post, %Q{#{base_url}/delete/#{service_name}/#{section_name}/#{graph_name_does_not_exist}}).to_return(status: 404)
    stub_request(:post, %Q{#{base_url}/delete_complex/#{service_name}/#{section_name}/#{complex_graph_name}}).to_return(body: '{"error":0}')

    # edit graph
    stub_request(:post, %Q{#{base_url}/edit/#{service_name}/#{section_name}/#{graph_name_does_not_exist}}).to_return(status: 404)
    ## with valid `color`
    stub_request(:post, %Q{#{base_url}/edit/#{service_name}/#{section_name}/#{graph_name}}).
      with(body: { color: '#000000', sort: true, description: true, graph_name: 'test_database', section_name: 'test_host', service_name: 'test_service' }).
        to_return(status: 200, body: '{"error":0}')
    ## with invalid `color`
    stub_request(:post, %Q{#{base_url}/edit/#{service_name}/#{section_name}/#{graph_name}}).
      with(body: { color: 'invalid color code', sort: true, description:true, graph_name: 'test_database', section_name: 'test_host', service_name: 'test_service' }).
        to_return(status: 400, body: '{"error":1,"messages":{"color":"#000000の形式で入力してください"}}')
    ## with valid `sort`
    stub_request(:post, %Q{#{base_url}/edit/#{service_name}/#{section_name}/#{graph_name}}).
      with(body: { sort: '10', color: true, description: true, graph_name: 'test_database', section_name: 'test_host', service_name: 'test_service' }).
        to_return(status: 200, body: '{"error":0}')
    ## with invalid `sort`
    stub_request(:post, %Q{#{base_url}/edit/#{service_name}/#{section_name}/#{graph_name}}).
      with(body: { sort: 'invalid sort num', color: true, description:true, graph_name: 'test_database', section_name: 'test_host', service_name: 'test_service' }).
        to_return(status: 400, body: '{"error":1,"messages":{"sort":"値が正しくありません"}}')

    # add complex
    ## with valid `stack` 
    stub_request(:post, %Q{#{base_url}/add_complex}).
      with(body: { stack: '0', description: true, graph_name: 'test_complex', :'path-data' => '2', section_name: 'test_host', service_name: 'test_service', sort: '19' }).
        to_return(status: 200, body: '{"error":0}')
    ## with invalid `stack` 
    stub_request(:post, %Q{#{base_url}/add_complex}).
      with(body: { stack: 'invalid stack num', description: true, graph_name: 'test_complex', :'path-data' => '2', section_name: 'test_host', service_name: 'test_service', sort: '19' }).
        to_return(status: 400, body: '{"error":1,"messages":{"stack":"スタックの値が正しくありません"}}')

    stub_request(:get, %Q{#{base_url}/view/#{service_name}/#{section_name}/#{graph_name}})
    stub_request(:get, %Q{#{base_url}/view/#{service_name}/#{section_name}/#{graph_name2}})
    stub_request(:get, %Q{#{base_url}/view/#{service_name}/#{section_name}/#{graph_name_does_not_exist}}).to_return(status: 404)
    stub_request(:get, %Q{#{base_url}/view_complex/#{service_name}/#{section_name}/#{complex_graph_name}})
    stub_request(:get, %Q{#{base_url}/json/#{service_name}/#{section_name}/#{graph_name}}).to_return(body: '{"error":0,"metricses":[{"id":"1"}]}')
    stub_request(:get, %Q{#{base_url}/json/#{service_name}/#{section_name}/#{graph_name2}}).to_return(body: '{"error":0,"metricses":[{"id":"2"}]}')
    stub_request(:get, %Q{#{base_url}/json/#{service_name}/#{section_name}/#{graph_name_does_not_exist}}).to_return(stauts: 404, body: '404')
  end
end

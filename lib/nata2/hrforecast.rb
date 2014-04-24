require 'nata2'
require 'net/http'
require 'json'

class Nata2::HRForecast
  def initialize(fqdn, port, https: false)
    scheme = https ? 'https://' : 'http://'
    @base_url = "#{scheme}#{fqdn}:#{port}"
  end

  # datetime support format: #{@base_url}/docs
  def update(service_name, section_name, graph_name, value, datetime: Time.now, color: nil)
    graph_path = [service_name, section_name, graph_name].join('/')

    response = if color && !graph_exist?(service_name, section_name, graph_name)
                 res = post('api/' + graph_path, number: value, datetime: datetime.to_s)
                 edit_graph(service_name, section_name, graph_name, color: color)
                 res
               else
                 post('api/' + graph_path, number: value, datetime: datetime.to_s)
               end

    response
  end

  def edit_graph(service_name, section_name, graph_name, color: nil, description: nil, sort: 0)
    graph_path = [service_name, section_name, graph_name].join('/')

    post('edit/' + graph_path, {
      service_name: service_name,
      section_name: section_name,
      graph_name: graph_name,
      description: description,
      sort: sort, # display in the list in descending order of value (0..19)
      color: color
    })
  end

  def create_complex_graph(service_name, section_name, graph_name, graph_ids, description: nil, stack: 1, sort: 19)
    post('add_complex', {
      service_name: service_name,
      section_name: section_name,
      graph_name: graph_name,
      description: description,
      stack: stack, # 0: stacked graph, 1: non-stacked graph
      sort: sort, # display in the list in descending order of value (0..19)
      :'path-data' => graph_ids # Array of graph IDs
    })
  end

  def delete_graph(service_name, section_name, graph_name)
    graph_path = [service_name, section_name, graph_name].join('/')
    post('delete/' + graph_path)
  end

  def delete_complex_graph(service_name, section_name, graph_name)
    graph_path = [service_name, section_name, graph_name].join('/')
    post('delete_complex/' + graph_path)
  end

  def graph_exist?(service_name, section_name, graph_name, path_prefix = '/view')
    uri = URI.parse(@base_url + [path_prefix, service_name, section_name, graph_name].join('/'))
    request = Net::HTTP::Get.new(uri.path)
    response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
    response && response.is_a?(Net::HTTPSuccess)
  end

  def complex_graph_exist?(service_name, section_name, graph_name)
    graph_exist?(service_name, section_name, graph_name, '/view_complex')
  end

  private

  def post(path, form_data = {})
    uri = URI.parse("#{@base_url}/#{path}")
    request = Net::HTTP::Post.new(uri.path)
    request.set_form_data(form_data)
    response = Net::HTTP.new(uri.host, uri.port).start { |http| http.request(request) }

    if !response
      raise
    end

    result = JSON.parse(response.body, symbolize_names: true)

    if result[:error] != 0
      raise RuntimeError, result[:messages].to_s
    end

    result
  end
end

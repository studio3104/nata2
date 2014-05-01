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
                 post('api/' + graph_path, number: value, datetime: datetime.to_s)
                 edit_graph(service_name, section_name, graph_name, color: color)
               else
                 post('api/' + graph_path, number: value, datetime: datetime.to_s)
               end

    response[:metricses].first
  end

  def create_complex_graph(service_name, section_name, graph_name, graph_ids, description: nil, stack: 0, sort: 19)
    post('add_complex', {
      service_name: service_name,
      section_name: section_name,
      graph_name: graph_name,
      description: description,
      stack: stack, # 0: non-stacked graph, 1: stacked graph
      sort: sort, # display in the list in descending order of value (0..19)
      :'path-data' => graph_ids # Array of graph IDs
    })
  end

  def edit_graph(service_name, section_name, graph_name, color: nil, description: nil, sort: nil)
    graph_path = [service_name, section_name, graph_name].join('/')

    contents = {
      service_name: service_name,
      section_name: section_name,
      graph_name: graph_name,
    }

    graph_current_status = graph_status(service_name, section_name, graph_name)
    contents[:description] = description || graph_current_status[:description]
    contents[:sort] = sort || graph_current_status[:sort] # display in the list in descending order of value (0..19)
    contents[:color] = color || graph_current_status[:color]
    post('edit/' + graph_path, contents)
  end

  def edit_complex_graph(service_name, section_name, graph_name, graph_ids: nil, description: nil, stack: nil, sort: nil)
    graph_path = [service_name, section_name, graph_name].join('/')

    contents = {
      service_name: service_name,
      section_name: section_name,
      graph_name: graph_name,
    }

    graph_current_status = complex_graph_status(service_name, section_name, graph_name)
    contents[:'path-data'] = graph_ids || graph_current_status[:'path-data']
    contents[:description] = description || graph_current_status[:description]
    contents[:sort] = sort || graph_current_status[:sort] # display in the list in descending order of value (0..19)
    contents[:stack] = stack || graph_current_status[:stack]
    post('edit_complex/' + graph_path, contents)
  end

  def add_graphs_to_complex(service_name, section_name, graph_name, graph_ids)
    graph_current_status = complex_graph_status(service_name, section_name, graph_name)
    graph_ids = (graph_current_status[:'path-data'] + graph_ids).uniq

    unless graph_ids.sort == graph_current_status[:'path-data'].sort
      edit_complex_graph(service_name, section_name, graph_name, graph_ids: graph_ids)
    end
  end

  def delete_graphs_from_complex(service_name, section_name, graph_name, graph_ids)
    graph_current_status = complex_graph_status(service_name, section_name, graph_name)
    graph_ids = (graph_current_status[:'path-data'] - graph_ids).uniq

    unless graph_ids.sort == graph_current_status[:'path-data'].sort
      edit_complex_graph(service_name, section_name, graph_name, graph_ids: graph_ids)
    end
  end

  def delete_graph(service_name, section_name, graph_name)
    graph_path = [service_name, section_name, graph_name].join('/')
    post('delete/' + graph_path)
  end

  def delete_complex_graph(service_name, section_name, graph_name)
    graph_path = [service_name, section_name, graph_name].join('/')
    post('delete_complex/' + graph_path)
  end

  def graph_exist?(service_name, section_name, graph_name, path_prefix = 'view/')
    graph_path = [service_name, section_name, graph_name].join('/')
    response = get(path_prefix + graph_path)
    response && response.is_a?(Net::HTTPSuccess)
  end

  def complex_graph_exist?(service_name, section_name, graph_name)
    graph_exist?(service_name, section_name, graph_name, 'view_complex/')
  end

  def graph_status(service_name, section_name, graph_name, path_prefix = 'json/')
    raise RuntimeError unless graph_exist?(service_name, section_name, graph_name, path_prefix == 'json/' ? 'view/' : 'view_complex/')
    graph_path = [service_name, section_name, graph_name].join('/')
    response = get(path_prefix + graph_path)

    if !response || response.is_a?(Net::HTTPNotFound)
      raise RuntimeError
    end

    result = JSON.parse(response.body, symbolize_names: true)
    if result[:error] != 0
      raise RuntimeError, result[:messages].to_s
    end
    result[:metricses].first
  end

  def complex_graph_status(service_name, section_name, graph_name)
    graph_status(service_name, section_name, graph_name, 'json_complex/')
  end

  private

  def get(path)
    uri = URI.parse("#{@base_url}/#{path}")
    request = Net::HTTP::Get.new(uri.path)
    Net::HTTP.new(uri.host, uri.port).start { |http| http.request(request) }
  end

  def post(path, form_data = {})
    uri = URI.parse("#{@base_url}/#{path}")
    request = Net::HTTP::Post.new(uri.path)
    request.set_form_data(form_data)
    response = Net::HTTP.new(uri.host, uri.port).start { |http| http.request(request) }

    if !response || response.is_a?(Net::HTTPNotFound)
      raise RuntimeError
    end

    result = JSON.parse(response.body, symbolize_names: true)

    if result[:error] != 0
      raise RuntimeError, result[:messages].to_s
    end

    result
  end
end

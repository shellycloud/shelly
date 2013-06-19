class Shelly::Client
  def application_logs(cloud, options = {})
    get("/apps/#{cloud}/application_logs#{query(options)}")
  end

  def application_logs_tail(cloud)
    url = get("/apps/#{cloud}/application_logs/tail")["url"]
    options = {
      :url            => url,
      :method         => :get,
      :timeout        => 60 * 60 * 24,
      :block_response => Proc.new { |r| r.read_body { |c| yield(c) } }
    }.merge(http_basic_auth_options)
    RestClient::Request.execute(options)
  end

  def download_application_logs_attributes(code_name, options)
    attributes = get("/apps/#{code_name}/application_logs/download#{query(options)}")
    headers = RestClient::Request.execute({
      :method => :get,
      :url => "#{attributes["url"]}/headers"
    }.merge(http_basic_auth_options)).headers

    attributes.merge("size" => headers[:content_lenght].to_i)
  end
end

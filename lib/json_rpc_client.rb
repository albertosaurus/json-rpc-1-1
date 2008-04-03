#
# This is the JSON-RPC Client, the handler for the client side of a JSON-RPC 
# connection.
#
class JsonRpcClient
  
  require 'json'
  require 'net/http'
  require 'uri'
  
    
  #
  # Our runtime error class.
  #
  class Error < RuntimeError; end
  
  
  #
  # Execute this "declaration" with a string or URI object describing the base URI
  # of the JSON-RPC service you want to connect to, e.g. 'http://213.86.231.12/my_services'.
  # NB: avoid host names at all costs, since Net::HTTP can be slow resolving them. Use raw
  # IP numbers instead - the difference is in the order of a couple of magnitudes on my
  # system. If you wish, pass :persistent => true to make the connection persistent. If you
  # do, you are responsible for closing the HTTP connection when you are done, using 
  # close_service(). If there is a proxy, pass :proxy => 'http://123.45.32.45:8080' or similar.
  #
  def self.json_rpc_service(base_uri, opts={})
    @uri = URI.parse base_uri
    @host = @uri.host
    @port = @uri.port
    @proxy = opts[:proxy] && URI.parse(opts[:proxy])
    @proxy_host = opts[:proxy] && @proxy.host
    @proxy_port = opts[:proxy] && @proxy.port
    @http = opts[:persistent] && Net::HTTP.start(@host, @port, @proxy_host, @proxy_port)
    @procs = {}
    @get_procs = []
    @post_procs = []
    @uri
  end
  
  
  def self.close_service
    @http.finish
  end
      

  #
  # This allows us to call methods remotely with the same syntax as if they were local.
  # If your client object is +service+, you can simply evaluate +service.whatever(:a => 100, :b => [1,2,3])+
  # or whatever you need. Positional and named arguments are fully supported according
  # to the JSON-RPC 1.1 specifications.
  #
  def self.method_missing(name, *args)
    system_describe unless @service_description
    name = name.to_s
    req_wrapper = @get_procs.include?(name) ? Get.new(self, name, args) : Post.new(self, name, args)
    req = req_wrapper.req
    Net::HTTP.start(@host, @port, @proxy_host, @proxy_port) do |http|
      res = http.request req
      json = JSON.parse res.body
      raise Error, "JSON-RPC error #{json['error']['code']}: #{json['error']['message']}" if json['error']
      json['result']
    end
  end
      

  #
  # The basic path of the service, i.e. '/services'.
  #
  def self.service_path
    @uri.path
  end
  
  
  #
  # The hash of callable remote procs descriptions
  #
  def self.procs
    @procs
  end
      
      
  #
  # Scream if called the old way.
  #
  def initialize(base_uri, opts={})
    raise "You are no longer supposed to instantiate classes inherited from JsonRpcClient."
  end  
  
  
  #
  # This method is called automatically as soon as a client is created. It polls the
  # service for its +system.describe+ information, which the client uses to find out
  # whether to call a remote procedure using GET or POST (depending on idempotency).
  # You can of course use this information in any way you want.
  #
  def self.system_describe
    @service_description = :in_progress
    @service_description = method_missing('system.describe')
    @service_description['procs'].each do |p|
      @post_procs << p['name']
      @get_procs << p['name'] if p['idempotent']
    end
    @service_description['procs'].each { |p| @procs[p['name']] = p }
    @service_description
  end
      
      
  #
  # This is a simple class wrapper for Net::HTTP::Post and Get objects.
  # They require slightly different initialisation.
  #    
  class Request
    
    attr_reader :req
          
    
    #
    # Sets the HTTP headers required for both GET and POST requests.
    #      
    def initialize
      @req.initialize_http_header 'User-Agent' => 'Ruby JSON-RPC Client 1.1',
                                  'Accept' => 'application/json'
    end
    
  end
  
  
  #
  # GET requests are only made for idempotent procedures, which allows these
  # requests to get cached, etc. (A procedure is declared idempotent on the
  # service side, by specifying :idempotent => true.) GET requests pass all
  # their args in the URI itself, as part of the query string. Positional
  # args are supported, as well as named args. If a call has only a hash
  # as its only argument, the key/val pairs are used as name/value pairs.
  # All other situations pass hashes in their entirety as just one of the args 
  # in the arglist.  
  #
  class Get < Request
    def initialize(klass, name, args)
      if args.length == 0
        query = ''
      elsif args.length == 1 && args[0].is_a?(Hash)
        # If we get an array where the first and only element is a hash, we apply the hash (named args).
        pairs = []
        args[0].each do |key, val|
          pairs << "#{key}=#{URI.encode val.to_s}"
        end
        query = '?' + pairs.join('&')
      else
        pairs = []
        procpar = klass.procs[name]['params']
        args.each_with_index do |val, i|
          key = procpar[i]['name']
          pairs << "#{key}=#{URI.encode val.to_s}"
        end
        query = '?' + pairs.join('&')
      end
      @req = Net::HTTP::Get.new(klass.service_path + '/' + name + query)
      super()
    end
    
  end
  
  
  #
  # Unless we know that a procedure is idempotent, a POST call will be used.
  # In case anyone wonders, GET and POST requests are roughly of the same
  # speed - GETs require slightly more processing on the client side, while 
  # POSTs require slightly more processing on the service side.
  #
  class Post < Request
    
    def initialize(klass, name, args)
      @req = Net::HTTP::Post.new(klass.service_path)
      super()
      @req.add_field 'Content-Type', 'application/json'
      @req.body = { :version => '1.1', :method => name, :params => args }.to_json
    end
    
  end
  
end # of JsonRpcClient
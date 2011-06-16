#
# This exception should be thrown by Rails in a JSON-RPC method to return a specific error id/message to the client.
#
class JsonRpcException < Exception
  
  attr_reader :error_id
  
  def initialize(error_id, err_message)
    super(err_message)
    @error_id = error_id
  end
end
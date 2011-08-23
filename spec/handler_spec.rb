$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../lib'))

require 'rubygems'
require 'dav4rack'
require 'fileutils'
require 'nokogiri'

describe DAV4Rack::Handler do
  DOC_ROOT = File.expand_path(File.dirname(__FILE__) + '/htdocs')
  METHODS = %w(GET PUT POST DELETE PROPFIND PROPPATCH MKCOL COPY MOVE OPTIONS HEAD LOCK UNLOCK)  
  
  before do
    FileUtils.mkdir(DOC_ROOT) unless File.exists?(DOC_ROOT)
    @controller = DAV4Rack::Handler.new(:root => DOC_ROOT)
  end

  after do
    FileUtils.rm_rf(DOC_ROOT) if File.exists?(DOC_ROOT)
  end
  
  attr_reader :response
  
  def request(method, uri, options={})
    options = {
      'HTTP_HOST' => 'localhost',
      'REMOTE_USER' => 'user'
    }.merge(options)
    request = Rack::MockRequest.new(@controller)
    @response = request.request(method, uri, options)
  end

  METHODS.each do |method|
    define_method(method.downcase) do |*args|
      request(method, *args)
    end
  end  
  
  def render(root_type)
    raise ArgumentError.new 'Expecting block' unless block_given?
    doc = Nokogiri::XML::Builder.new do |xml_base|
      xml_base.send(root_type.to_s, 'xmlns:D' => 'D:') do
        xml_base.parent.namespace = xml_base.parent.namespace_definitions.first
        xml = xml_base['D']
        yield xml
      end
    end
    doc.to_xml
  end
 
  def url_escape(string)
    string.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
      '%' + $1.unpack('H2' * $1.size).join('%').upcase
    end.tr(' ', '+')
  end
  
  def response_xml
    Nokogiri.XML(@response.body)
  end
  
  def multistatus_response(pattern)
    @response.should be_multi_status
    response_xml.xpath('//D:multistatus/D:response', response_xml.root.namespaces).should_not be_empty
    response_xml.xpath("//D:multistatus/D:response#{pattern}", response_xml.root.namespaces)
  end

  def multi_status_created
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /Created/
  end
  
  def multi_status_ok
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /OK/
  end
  
  def multi_status_no_content
    response_xml.xpath('//D:multistatus/D:response/D:status').should_not be_empty
    response_xml.xpath('//D:multistatus/D:response/D:status').text.should =~ /No Content/
  end
  
  def propfind_xml(*props)
    render(:propfind) do |xml|
      xml.prop do
        props.each do |prop|
        xml.send(prop.to_sym)
        end
      end
    end
  end
  
  it 'should return all options' do
    options('/').should be_ok
    
    METHODS.each do |method|
      response.headers['allow'].should include(method)
    end
  end
  
  it 'should return headers' do
    put('/test.html', :input => '<html/>').should be_created
    head('/test.html').should be_ok
    
    response.headers['etag'].should_not be_nil
    response.headers['content-type'].should match(/html/)
    response.headers['last-modified'].should_not be_nil
  end
  
  it 'should not find a nonexistent resource' do
    get('/not_found').should be_not_found
  end
  
  it 'should not allow directory traversal' do
    get('/../htdocs').should be_forbidden
  end
  
  it 'should create a resource and allow its retrieval' do
    put('/test', :input => 'body').should be_created
    get('/test').should be_ok
    response.body.should == 'body'
  end

  it 'should return an absolute url after a put request' do
    put('/test', :input => 'body').should be_created
    response['location'].should =~ /http:\/\/localhost(:\d+)?\/test/
  end
  
  it 'should create and find a url with escaped characters' do
    put(url_escape('/a b'), :input => 'body').should be_created
    get(url_escape('/a b')).should be_ok
    response.body.should == 'body'
  end
  
  it 'should delete a single resource' do
    put('/test', :input => 'body').should be_created
    delete('/test').should be_no_content
  end
  
  it 'should delete recursively' do
    mkcol('/folder')
    multi_status_created.should eq true
    put('/folder/a', :input => 'body').should be_created
    put('/folder/b', :input => 'body').should be_created
    
    delete('/folder').should be_no_content
    get('/folder').should be_not_found
    get('/folder/a').should be_not_found
    get('/folder/b').should be_not_found
  end

  it 'should not allow copy to another domain' do
    put('/test', :input => 'body').should be_created
    copy('http://localhost/', 'HTTP_DESTINATION' => 'http://another/').should be_bad_gateway
  end

  it 'should not allow copy to the same resource' do
    put('/test', :input => 'body').should be_created
    copy('/test', 'HTTP_DESTINATION' => '/test').should be_forbidden
  end

  it 'should copy a single resource' do
    put('/test', :input => 'body').should be_created
    copy('/test', 'HTTP_DESTINATION' => '/copy')
    multi_status_no_content.should eq true
    get('/copy').body.should == 'body'
  end

  it 'should copy a resource with escaped characters' do
    put(url_escape('/a b'), :input => 'body').should be_created
    copy(url_escape('/a b'), 'HTTP_DESTINATION' => url_escape('/a c'))
    multi_status_no_content.should eq true
    get(url_escape('/a c')).should be_ok
    response.body.should == 'body'
  end
  
  it 'should deny a copy without overwrite' do
    put('/test', :input => 'body').should be_created
    put('/copy', :input => 'copy').should be_created
    copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'F')
    
    multistatus_response('/D:href').first.text.should =~ /http:\/\/localhost(:\d+)?\/test/
    multistatus_response('/D:status').first.text.should match(/412 Precondition Failed/)
    
    get('/copy').body.should == 'copy'
  end
  
  it 'should allow a copy with overwrite' do
    put('/test', :input => 'body').should be_created
    put('/copy', :input => 'copy').should be_created
    copy('/test', 'HTTP_DESTINATION' => '/copy', 'HTTP_OVERWRITE' => 'T')
    multi_status_no_content.should eq true
    get('/copy').body.should == 'body'
  end
  
  it 'should copy a collection' do  
    mkcol('/folder')
    multi_status_created.should eq true
    copy('/folder', 'HTTP_DESTINATION' => '/copy')
    multi_status_ok.should eq true
    propfind('/copy', :input => propfind_xml(:resourcetype))
    multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection').should_not be_empty
  end

  it 'should copy a collection resursively' do
    mkcol('/folder')
    multi_status_created.should eq true
    put('/folder/a', :input => 'A').should be_created
    put('/folder/b', :input => 'B').should be_created
    
    copy('/folder', 'HTTP_DESTINATION' => '/copy')
    multi_status_ok.should eq true
    propfind('/copy', :input => propfind_xml(:resourcetype))
    multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection').should_not be_empty
    get('/copy/a').body.should == 'A'
    get('/copy/b').body.should == 'B'
  end
  
  it 'should move a collection recursively' do
    mkcol('/folder')
    multi_status_created.should eq true
    put('/folder/a', :input => 'A').should be_created
    put('/folder/b', :input => 'B').should be_created
    
    move('/folder', 'HTTP_DESTINATION' => '/move')
    multi_status_ok.should eq true
    propfind('/move', :input => propfind_xml(:resourcetype))
    multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection').should_not be_empty    
    
    get('/move/a').body.should == 'A'
    get('/move/b').body.should == 'B'
    get('/folder/a').should be_not_found
    get('/folder/b').should be_not_found
  end
  
  it 'should create a collection' do
    mkcol('/folder')
    multi_status_created.should eq true
    propfind('/folder', :input => propfind_xml(:resourcetype))
    multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection').should_not be_empty
  end
  
  it 'should return full urls after creating a collection' do
    mkcol('/folder')
    multi_status_created.should eq true
    propfind('/folder', :input => propfind_xml(:resourcetype))
    multistatus_response('/D:propstat/D:prop/D:resourcetype/D:collection').should_not be_empty
    multistatus_response('/D:href').first.text.should =~ /http:\/\/localhost(:\d+)?\/folder/
  end
  
  it 'should not find properties for nonexistent resources' do
    propfind('/non').should be_not_found
  end
  
  it 'should find all properties' do
    xml = render(:propfind) do |xml|
      xml.allprop
    end
    
    propfind('http://localhost/', :input => xml)
    
    multistatus_response('/D:href').first.text.strip.should =~ /http:\/\/localhost(:\d+)?\//

    props = %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    props.each do |prop|
      multistatus_response("/D:propstat/D:prop/D:#{prop}").should_not be_empty
    end
  end
  
  it 'should find named properties' do
    put('/test.html', :input => '<html/>').should be_created
    propfind('/test.html', :input => propfind_xml(:getcontenttype, :getcontentlength))
   
    multistatus_response('/D:propstat/D:prop/D:getcontenttype').first.text.should == 'text/html'
    multistatus_response('/D:propstat/D:prop/D:getcontentlength').first.text.should == '7'
  end

  it 'should lock a resource' do
    put('/test', :input => 'body').should be_created
    
    xml = render(:lockinfo) do |xml|
      xml.lockscope { xml.exclusive }
      xml.locktype { xml.write }
      xml.owner { xml.href "http://test.de/" }
    end

    lock('/test', :input => xml)
    
    response.should be_ok
    
    match = lambda do |pattern|
      response_xml.xpath "/D:prop/D:lockdiscovery/D:activelock#{pattern}"
    end
    
    match[''].should_not be_empty

    match['/D:locktype'].should_not be_empty
    match['/D:lockscope'].should_not be_empty
    match['/D:depth'].should_not be_empty
    match['/D:timeout'].should_not be_empty
    match['/D:locktoken'].should_not be_empty
    match['/D:owner'].should_not be_empty
  end
  
  context "when mapping a path" do
    
    before do
      @controller = DAV4Rack::Handler.new(:root => DOC_ROOT, :root_uri_path => '/webdav/')
    end
    
    it "should return correct urls" do
      # FIXME: a put to '/test' works, too -- should it?
      put('/webdav/test', :input => 'body').should be_created
      response.headers['location'].should =~ /http:\/\/localhost(:\d+)?\/webdav\/test/
    end
  end
end

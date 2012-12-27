require 'spec_helper'

describe Grape::Middleware::Formatter do
  subject{ Grape::Middleware::Formatter.new(app) }
  before{ subject.stub!(:dup).and_return(subject) }

  let(:app){ lambda{|env| [200, {}, [@body]]} }

  context 'serialization' do
    it 'looks at the bodies for possibly serializable data' do
      @body = {"abc" => "def"}
      status, headers, bodies = *subject.call({'PATH_INFO' => '/somewhere', 'HTTP_ACCEPT' => 'application/json'})
      bodies.each{|b| b.should == MultiJson.dump(@body) }
    end

    it 'calls #to_json since default format is json' do
      @body = ['foo']
      @body.instance_eval do
        def to_json
          "\"bar\""
        end
      end

      subject.call({'PATH_INFO' => '/somewhere', 'HTTP_ACCEPT' => 'application/json'}).last.each{|b| b.should == '"bar"'}
    end

    it 'calls #to_xml if the content type is xml' do
      @body = "string"
      @body.instance_eval do
        def to_xml
          "<bar/>"
        end
      end

      subject.call({'PATH_INFO' => '/somewhere.xml', 'HTTP_ACCEPT' => 'application/json'}).last.each{|b| b.should == '<bar/>'}
    end
  end

  context 'detection' do
    it 'uses the extension if one is provided' do
      subject.call({'PATH_INFO' => '/info.xml'})
      subject.env['api.format'].should == :xml
      subject.call({'PATH_INFO' => '/info.json'})
      subject.env['api.format'].should == :json
    end

    it 'uses the format parameter if one is provided' do
      subject.call({'PATH_INFO' => '/somewhere','QUERY_STRING' => 'format=json'})
      subject.env['api.format'].should == :json
      subject.call({'PATH_INFO' => '/somewhere','QUERY_STRING' => 'format=xml'})
      subject.env['api.format'].should == :xml
    end

    it 'uses the default format if none is provided' do
      subject.call({'PATH_INFO' => '/info'})
      subject.env['api.format'].should == :txt
    end

    it 'uses the requested format if provided in headers' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json'})
      subject.env['api.format'].should == :json
    end

    it 'uses the file extension format if provided before headers' do
      subject.call({'PATH_INFO' => '/info.txt', 'HTTP_ACCEPT' => 'application/json'})
      subject.env['api.format'].should == :txt
    end
  end

  context 'Accept header detection' do
    it 'detects from the Accept header' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/xml'})
      subject.env['api.format'].should == :xml
    end

    it 'looks for case-indifferent headers' do
      subject.call({'PATH_INFO' => '/info', 'http_accept' => 'application/xml'})
      subject.env['api.format'].should == :xml
    end

    it 'uses quality rankings to determine formats' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json; q=0.3,application/xml; q=1.0'})
      subject.env['api.format'].should == :xml
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json; q=1.0,application/xml; q=0.3'})
      subject.env['api.format'].should == :json
    end

    it 'handles quality rankings mixed with nothing' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json,application/xml; q=1.0'})
      subject.env['api.format'].should == :xml
    end

    it 'parses headers with other attributes' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json; abc=2.3; q=1.0,application/xml; q=0.7'})
      subject.env['api.format'].should == :json
    end

    it 'parses headers with vendor and api version' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/vnd.test-v1+xml'})
      subject.env['api.format'].should == :xml
    end

    it 'parses headers with symbols as hash keys' do
      subject.call({'PATH_INFO' => '/info', 'http_accept' => 'application/xml', :system_time => '091293'})
      subject.env[:system_time].should == '091293'
    end
  end

  context 'Content-type' do
    it 'is set for json' do
      _, headers, _ = subject.call({'PATH_INFO' => '/info.json'})
      headers['Content-type'].should == 'application/json'
    end
    it 'is set for xml' do
      _, headers, _ = subject.call({'PATH_INFO' => '/info.xml'})
      headers['Content-type'].should == 'application/xml'
    end
    it 'is set for txt' do
      _, headers, _ = subject.call({'PATH_INFO' => '/info.txt'})
      headers['Content-type'].should == 'text/plain'
    end
    it 'is set for custom' do
      subject.options[:content_types] = {}
      subject.options[:content_types][:custom] = 'application/x-custom'
      _, headers, _ = subject.call({'PATH_INFO' => '/info.custom'})
      headers['Content-type'].should == 'application/x-custom'
    end
  end

  context 'Format' do
    it 'uses custom formatter' do
      subject.options[:content_types] = {}
      subject.options[:content_types][:custom] = "don't care"
      subject.options[:formatters][:custom] = lambda { |obj, env| 'CUSTOM FORMAT' }
      _, _, body = subject.call({'PATH_INFO' => '/info.custom'})
      body.body.should == ['CUSTOM FORMAT']
    end
    it 'uses default json formatter' do
      @body = ['blah']
      _, _, body = subject.call({'PATH_INFO' => '/info.json'})
      body.body.should == ['["blah"]']
    end
    it 'uses custom json formatter' do
      subject.options[:formatters][:json] = lambda { |obj, env| 'CUSTOM JSON FORMAT' }
      _, _, body = subject.call({'PATH_INFO' => '/info.json'})
      body.body.should == ['CUSTOM JSON FORMAT']
    end
  end

  context 'Input' do
    it 'parses the body from a POST/PUT and put the contents into rack.request.form_hash' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json', 'rack.input' => StringIO.new('{"is_boolean":true,"string":"thing"}')})
      subject.env['rack.request.form_hash']['is_boolean'].should be_true
      subject.env['rack.request.form_hash']['string'].should == 'thing'
    end
    it 'parses the body from an xml POST/PUT and put the contents into rack.request.from_hash' do
      subject.call({'PATH_INFO' => '/info.xml', 'HTTP_ACCEPT' => 'application/xml', 'rack.input' => StringIO.new('<thing><name>Test</name></thing>')})
      subject.env['rack.request.form_hash']['thing']['name'].should == 'Test'
    end
    it 'is able to fail gracefully if the body is regular POST content' do
      subject.call({'PATH_INFO' => '/info', 'HTTP_ACCEPT' => 'application/json', 'rack.input' => StringIO.new('name=Other+Test+Thing')})
      subject.env['rack.request.form_hash'].should be_nil
    end
  end
end

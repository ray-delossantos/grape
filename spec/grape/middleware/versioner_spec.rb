require 'spec_helper'

describe Grape::Middleware::Versioner do
  
  let(:klass) { Grape::Middleware::Versioner }

  it 'recognizes :path' do
    klass.using(:path).should == Grape::Middleware::Versioner::Path
  end

  it 'recognizes :header' do
    klass.using(:header).should == Grape::Middleware::Versioner::Header
  end

  it 'recognizes :param' do
    klass.using(:param).should == Grape::Middleware::Versioner::Param
  end

end
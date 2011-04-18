require 'rubygems'

# parent of ProviderImage is Image, parent of Image is Template, parent of Template is Assembly, parent of Assembly is Deployable

module IWHDInterface

  require 'rest-client'
  require 'nokogiri'

  BASE_IWHD_URL = 'http://localhost:9090'

  def self.client
    RestClient::Resource.new(BASE_IWHD_URL)
  end

  class BaseObject
    def self.parents_of(uuid); []; end
    def self.children_of(uuid); []; end
  end

  class ProviderImage < BaseObject

    def self.parents_of(uuid)
      [ IWHDInterface::client["/provider_images/%s/image" % uuid].get ]
    end

  end

  class Image < BaseObject

    def self.children_of(uuid)
      (Nokogiri::XML(IWHDInterface::client["/provider_images"].get)/"/objects/object/key").collect do |provider_image_id|
        ProviderImage::parents_of(provider_image_id.text).empty? ? nil : provider_image_id.text
      end.compact
    end

    def self.parents_of(uuid)
      [ IWHDInterface::client["/images/%s/template" % uuid].get ]
    end

  end

  class Template < BaseObject

    def self.children_of(uuid)
      (Nokogiri::XML(IWHDInterface::client["/images"].get)/"/objects/object/key").collect do |image_id|
        Image::parents_of(image_id.text).empty? ? nil : image_id.text
      end.compact
    end

    def self.parents_of(uuid)
      [] # TODO: Assemblies here
    end

  end

  class Assembly < BaseObject

    def self.parents_of(uuid)
      raise 'Implement me!'
    end

    def self.children_of(uuid)
      raise 'Implement me!'
    end

  end

  class Deployable < BaseObject

    def self.children_of(uuid)
      raise 'Implement me!'
    end

  end

end

module IWHDInterface
  require 'sinatra/base'

  class REST < Sinatra::Base

    enable :inline_templates

    before do
      content_type 'application/xml'
    end

    get '/iwhd' do
      haml :index
    end

    get '/iwhd/:collection/:id/parents' do
      case params[:collection]
        when 'provider_images' then
            @parents = IWHDInterface::ProviderImage::parents_of(params[:id])
            @relation = :images
        when 'images' then
            @parents = IWHDInterface::Image::parents_of(params[:id])
            @relation = :templates
        when 'templates' then
            @parents = IWHDInterface::Template::parents_of(params[:id])
            @relation = :assemblies
      end
      haml :parents
    end

    get '/iwhd/:collection/:id/children' do
      case params[:collection]
        when 'images' then
            @parents = IWHDInterface::Image::children_of(params[:id])
            @relation = :provider_images
        when 'templates' then
            @parents = IWHDInterface::Template::children_of(params[:id])
            @relation = :images
      end
      haml :childrens
    end

    get '/iwhd/*' do
      response = IWHDInterface::client["/#{params[:splat]}"].get
      [response.code, response]
    end

  end
end

IWHDInterface::REST.run!

__END__

@@ layout
%iwhd{ :entrypoint => "#{IWHDInterface::BASE_IWHD_URL}"}
  = yield

@@ index
%collection{ :href => "/iwhd/provider_images", :rel => :provider_images}
  %link{ :href => "/iwhd/provider_images/:id/parents", :rel => :parents, :method => :get}
%collection{ :href => "/iwhd/images", :rel => :images}
  %link{ :href => "/iwhd/images/:id/children", :rel => :children, :method => :get}
  %link{ :href => "/iwhd/images/:id/parents", :rel => :parents, :method => :get}
%collection{ :href => "/iwhd/templates", :rel => :templates}
  %link{ :href => "/iwhd/templates/:id/children", :rel => :children, :method => :get}
  %link{ :href => "/iwhd/templates/:id/parents", :rel => :parents, :method => :get}
%collection{ :href => "/iwhd/icicles", :rel => :icicles}
%collection{ :href => "/iwhd/assemblies", :rel => :assemblies}
  %link{ :href => "/iwhd/assemblies/:id/children", :rel => :children, :method => :get}
  %link{ :href => "/iwhd/assemblies/:id/parents", :rel => :parents, :method => :get}
%collection{ :href => "/iwhd/deployables", :rel => :deployables}
  %link{ :href => "/iwhd/deployables/:id/children", :rel => :children, :method => :get}

@@childrens
- haml_tag "#{params[:collection]}".gsub(/s$/, ''), :href => "/iwhd/#{params[:collection]}/#{params[:id]}", :id => params[:id]  do
  - @parents.each do |uuid|
    %link{ :href => "/iwhd/#{@relation}/#{uuid}", :rel => "#{@relation.to_s.gsub(/s$/, '')}", :type => :child, :id => uuid}

@@parents
- haml_tag "#{params[:collection]}".gsub(/s$/, ''), :href => "/iwhd/#{params[:collection]}/#{params[:id]}", :id => params[:id]  do
  - @parents.each do |uuid|
    %link{ :href => "/iwhd/#{@relation}/#{uuid}", :rel => "#{@relation.to_s.gsub(/s$/, '')}", :type => :parent, :id => uuid}

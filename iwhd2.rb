require 'rubygems'

module  IWHDReferenceHelper

  require 'nokogiri'
  require 'rest-client'

  BASE_IWHD_URL = 'http://10.34.37.109:9090'

  def self.client
    RestClient::Resource.new(BASE_IWHD_URL)
  end

  # This method will store references to objects in IWHD from XML of deployable 
  # Input should be valid Deployable XML
  #
  # https://github.com/clalancette/audrey/blob/config-server/configserver/schema/deployable.rng
  #
  # FIXME: I added UUID to XML tags which are referencing objects in IWHD
  #
  def self.store_deployable!(body)
    deployable = Nokogiri::XML(body)
    deployable_uuid = (deployable/'deployable').first[:uuid]
    (deployable/'deployable/assemblies/assembly').each do |assembly| 
      IWHDReferenceHelper::Template.find_references_to_assembly(assembly[:uuid]) do |template|
        template.add_reference_to!('deployable', deployable_uuid)
      end
    end
  end

  # This method will store references to objects in IWHD from XML of assembly 
  # Input should be valid Assembly XML
  #
  # https://github.com/clalancette/audrey/blob/config-server/configserver/schema/assembly.rng
  #
  # FIXME: I added UUID to XML tags which are referencing objects in IWHD
  #
  def self.store_assembly!(body)
    assembly = Nokogiri::XML(body)
    assembly_uuid = (assembly/'assembly').first[:uuid]
    template_reference_id = (assembly/'assembly/template').first[:uuid]
    template = IWHDReferenceHelper::Template::new(template_reference_id)
    template.add_reference_to!('assembly', assembly_uuid)
  end

  class BaseObject

    attr_accessor :attributes
    attr_accessor :references
    attr_reader   :xml, :uuid

    def initialize(bucket, uuid)
      @bucket, @uuid = bucket, uuid
      @xml = Nokogiri::XML(IWHDReferenceHelper::client["/%s/%s/_attrs" % [bucket, uuid]].get)
      
      # Get list of attributes first
      self.attributes = (@xml/'object/object_attr').collect { |attr| attr[:name] }

      # Then select all attributes which are references
      self.references = self.attributes.select { |attr| starts_with?(attr, 'referenced_by_') }
      
      # Then strip out 'referenced_by_' string to produce just UUIDs
      self.references.collect! { |ref| ref.tr('referenced_by_', '')}
      self
    end

    # Prototypes
    def self.parents_of(uuid); []; end
    def self.children_of(uuid); []; end

    # Will add reference tag to target UUID (referenced_by_#{target})
    #
    def add_reference_to!(object, target)
      IWHDReferenceHelper::client["/%s/%s/referenced_by_%s" % [@bucket, @uuid, target]].put(:content => object)
    end

    private

    def starts_with?(string, prefix)
      string[0, prefix.to_s.length] == prefix.to_s
    end

  end

  class ProviderImage < BaseObject

    def self.parents_of(uuid)
      [ IWHDReferenceHelper::client["/provider_images/%s/image" % uuid].get ]
    end

  end

  class Image < BaseObject

    def initialize(uuid)
      super('images', uuid)
    end

    def self.children_of(uuid)
      (Nokogiri::XML(IWHDReferenceHelper::client["/provider_images"].get)/"/objects/object/key").collect do |provider_image_id|
        ProviderImage::parents_of(provider_image_id.text).empty? ? nil : provider_image_id.text
      end.compact
    end

    def self.parents_of(uuid)
      [ IWHDReferenceHelper::client["/images/%s/template" % uuid].get ]
    end

  end

  class Template < BaseObject
    def initialize(uuid)
      super('templates', uuid)
    end

    def reference_is_deployable?(uuid)
      true if IWHDReferenceHelper::client["/templates/%s/referenced_by_%s" % [self.uuid, uuid]].get.to_s.strip == 'content=deployable'
    end

    def reference_is_assembly?(uuid)
      true if IWHDReferenceHelper::client["/templates/%s/referenced_by_%s" % [self.uuid, uuid]].get.to_s.strip == 'content=assembly'
    end

    # This method will travel accross templates and find all references to
    # assemblies.
    def self.find_references_to_assembly(id)
      templates = Nokogiri::XML(IWHDReferenceHelper::client['/templates'].get).xpath('/objects/object/key').collect { |k| k.text }
      templates.each do |template_id|
        template = Template::new(template_id)
        yield template if template.references.include?(id)
      end
      return []
    end

    def self.children_of(uuid)
      (Nokogiri::XML(IWHDReferenceHelper::client["/images"].get)/"/objects/object/key").collect do |image_id|
        Image::parents_of(image_id.text).empty? ? nil : image_id.text
      end.compact
    end

    def self.parents_of(uuid)
      Template::new(uuid).references
    end

  end

  class Assembly < BaseObject

    def self.children_of(uuid)
      children = []
      Template::find_references_to_assembly(uuid) do |template|
        children << template.uuid
      end
      children
    end

    def self.parents_of(uuid)
      parents = []
      Template::find_references_to_assembly(uuid) do |template|
        template.references.each do |reference_id|
          parents << reference_id if IWHDReferenceHelper::Template::new(template.uuid).reference_is_deployable?(reference_id)
        end
      end
      parents
    end

  end

  class Deployable < BaseObject

    def self.children_of(uuid)
      parents = []
      Template::find_references_to_assembly(uuid) do |template|
        template.references.each do |reference_id|
          parents << reference_id if IWHDReferenceHelper::Template::new(template.uuid).reference_is_assembly?(reference_id)
        end
      end
      parents
    end

  end

end

=begin
require 'pp'

sample_assembly1= <<END
<assembly name="Assembly1" uuid="11111111-1111-11111-111111-11111111-2">
 <template type="Template-Type-1" uuid="7ad87a12-674a-11e0-965e-001a4a22203d"/>
 <services>
   <puppet>
     <service name="service-name">
       <class>puppet-class-name</class>
       <parameter name="param1-name">
         <value><![CDATA[Param1 Value]]></value>
       </parameter>
       <parameter name="param2-name">
         <reference assembly="Assembly2" parameter="param-from-asy2"/>
       </parameter>
     </service>
   </puppet>
 </services>
</assembly>
END

sample_assembly2= <<END
<assembly name="Assembly2" uuid="22222222-2222-22222-222222-222222222-2">
 <template type="Template-Type-2" uuid="7ad87a12-674a-11e0-965e-001a4a22203d"/>
 <services>
   <puppet>
     <service name="another-service-name">
       <class>puppet-class-name</class>
     </service>
   </puppet>
 </services>
</assembly>
END

sample_deployable1= <<END
<deployable name="Deployable1" uuid="3333333-33333-33333333-3333333333-333-2">
 <assemblies>
   <assembly name="MyAssembly1" type="Assembly1" hwp="large" uuid="22222222-2222-22222-222222-222222222-2"/>
   <assembly name="MyAssembly2" type="Assembly2" hwp="large" uuid="11111111-1111-11111-111111-111111111-2"/>
 </assemblies>
</deployable>
END


IWHDReferenceHelper::store_assembly!(sample_assembly1)
IWHDReferenceHelper::store_assembly!(sample_assembly2)
IWHDReferenceHelper::store_deployable!(sample_deployable1)

pp IWHDReferenceHelper::Assembly.children_of('11111111-1111-11111-111111-11111111-2')
# => ["7ad87a12-674a-11e0-965e-001a4a22203d"] # Referenced template ID


pp IWHDReferenceHelper::Assembly.parents_of('11111111-1111-11111-111111-11111111-2')
# => ["3333333-33333-33333333-3333333333-333-2"]

pp IWHDReferenceHelper::Deployable::children_of('3333333-33333-33333333-3333333333-333-2')
# => ["11111111-1111-11111-111111-11111111-2", "22222222-2222-22222-222222-222222222-2"]
=end


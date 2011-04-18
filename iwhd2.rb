require 'rubygems'

module  IWHDInterface

  require 'nokogiri'
  require 'rest-client'

  BASE_IWHD_URL = 'http://10.34.37.109:9090'

  def self.client
    RestClient::Resource.new(BASE_IWHD_URL)
  end

  def self.store_deployable!(body)
    deployable = Nokogiri::XML(body)
    deployable_uuid = (deployable/'deployable').first[:uuid]
    (deployable/'deployable/assemblies/assembly').each do |assembly| 
      IWHDInterface::Template.find_references_to_assembly(assembly[:uuid]) do |template|
        template.add_reference_to!(deployable_uuid)
      end
    end
  end

  def self.store_assembly!(body)
    assembly = Nokogiri::XML(body)
    assembly_uuid = (assembly/'assembly').first[:uuid]
    template_reference_id = (assembly/'assembly/template').first[:uuid]
    template = IWHDInterface::Template::new(template_reference_id)
    template.add_reference_to!(assembly_uuid)
  end

  class BaseObject

    attr_accessor :attributes
    attr_accessor :references
    attr_reader   :xml

    def initialize(bucket, uuid)
      @bucket, @uuid = bucket, uuid
      @xml = Nokogiri::XML(IWHDInterface::client["/%s/%s/_attrs" % [bucket, uuid]].get)
      parse_attributes!
      self.references = self.references.select { |attr| starts_with?(attr, 'referenced_by_') }.collect { |ref| ref.tr('referenced_by_', '')}
      self
    end

    def add_reference_to!(target)
      IWHDInterface::client["/%s/%s/referenced_by_%s" % [@bucket, @uuid, target]].put(:content => @bucket)
    end

    protected

    def parse_attributes!
      self.references = (@xml/'object/object_attr').collect { |attr| attr[:name] }
    end

    private

    def starts_with?(string, prefix)
      string[0, prefix.to_s.length] == prefix.to_s
    end

  end

  class Image < BaseObject
    def initialize(uuid)
      super('images', uuid)
    end
  end

  class Template < BaseObject
    def initialize(uuid)
      super('templates', uuid)
    end

    def self.find_references_to_assembly(id)
      templates = Nokogiri::XML(IWHDInterface::client['/templates'].get).xpath('/objects/object/key').collect { |k| k.text }
      templates.each do |template_id|
        template = Template::new(template_id)
        yield template if template.references.include?(id)
      end
    end
  end

end

require 'pp'

sample_assembly1= <<END
<assembly name="Assembly1" uuid="11111111-1111-11111-111111-111111111">
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
<assembly name="Assembly2" uuid="22222222-2222-22222-222222-222222222">
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
<deployable name="Deployable1" uuid="3333333-33333-33333333-3333333333-333">
 <assemblies>
   <assembly name="MyAssembly1" type="Assembly1" hwp="large" uuid="22222222-2222-22222-222222-222222222"/>
   <assembly name="MyAssembly2" type="Assembly2" hwp="large" uuid="11111111-1111-11111-111111-111111111"/>
 </assemblies>
</deployable>
END


#image = IWHDInterface::Image::new('b57cd61f-989c-4284-a9e6-4a5ae4499f8a')
# image.add_reference_to!('ec207843-c282-4108-9a6c-cdad2cc7f804')
# pp image.references

#IWHDInterface::store_assembly!(sample_assembly1)
#IWHDInterface::store_assembly!(sample_assembly2)
IWHDInterface::store_deployable!(sample_deployable1)

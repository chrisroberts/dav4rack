module DAV4Rack

  module Utils
    def to_element_hash(element)
      ns = element.namespace
      prefix = ns.nil? ? nil : ns.prefix
      href = ns.nil? ? nil : ns.href
      {:name => element.name, :ns_href => href, :children => element.children.collect{|e| to_element_hash(e)}}
    end

    def to_element_key(element)
      ns = element.namespace
      href = ns.nil? ? nil : ns.href
      "#{href}!!#{element.name}"
    end
  end

end

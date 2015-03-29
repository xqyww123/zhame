
def as obj, kind
  begin
    obj.kind = kind
  rescue NoMemoryError
    obj.instance_eval do
      class << self
        attr_accessor :kind
      end
    end unless obj.methods(false).include? :xqy
    obj.kind = kind
  end
end

def add_var obj, var_name, value=nil
  var_name = var_name.to_sym unless var_name.is_a? Symbol
  var_name_s = "@#{var_name}"
  obj.instance_eval do
    define_singleton_method(var_name){ instance_variable_get var_name_s }
    define_singleton_method(:"#{var_name}="){ |v| instance_variable_set var_name_s, v }
  end unless obj.methods(false).include? var_name
  obj.instance_variable_set var_name_s, value
  obj
end
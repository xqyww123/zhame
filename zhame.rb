VERSION = '0.1.0.0'
AUTHOR = 'xero'
MAIL = 'x@xeroe.net'

require 'slop'
require 'digest/hmac'
require 'digest/sha2'
require 'leveldb'
require 'yaml'
require 'pathname'
require 'ostruct'
require_relative 'xeros'
require 'base64'

class Zhame
  Language = Struct.new :words, :sperate, :short_len, :max_len
  Config = Struct.new :lan_hash_key, :kdb_ad, :pydb_ad, :lan_path

  def initialize config_path='config.yml'
    @cfg = YAML::load File.read config_path
    @lan = YAML::load File.read @cfg.lan_path
    @lan.words = @lan.words.split(//)
    @cfg.kdb_ad ||= 'kdb'
    @cfg.pydb_ad ||= 'pydb'
    @kdb = LevelDB::DB.new @cfg.kdb_ad
    @pydb = LevelDB::DB.new @cfg.pydb_ad
    #p YAML::load File.read 'pinyin_mandarin.yml'
    #load_py YAML::load File.read 'pinyin_mandarin.yml'
    #@pydb.close
    #exit
    @encodes = Hash[@lan.words.each_with_index.map {|a,i| [@pydb[a], i]}]
    raise 'no recorded ping ying found!' if @encodes.include? nil
    at_exit do
      @kdb.close
      @pydb.close
    end
  end

  def self.reset; @kdb.close; @pydb.close; end

  def name obj, **arg
    arg[:to_know] = true if arg[:to_know].nil?
    re = case (arg[:as] || obj)
           when String, :str
             name_bin Digest::HMAC.digest(obj, @cfg.lan_hash_key, Digest::SHA256)
           when Pathname, :path
             name_bin Digest::HMAC.file(obj, @cfg.lan_hash_key, Digest::SHA256).digest
           when :hex
             name_bin [obj].pack 'H*'
           else
             name_bin Digest::HMAC.digest(obj, @cfg.lan_hash_key, Digest::SHA256)
         end
    arg[:to_know] ? know(*re) : re
  end
  def know name, hex, full_name = name
    py = pylise(name).force_encoding 'utf-8'
    @kdb[py] = "#{full_name},#{Base64.encode64 hex},#{py},#{hex.valid_bits.to_s 16}" ; [name, hex]
  end
  def short name, code, **arg
    arg[:to_know] = true if arg[:to_know].nil?
    re = ''
    loop.each_with_index do |a,i|
      re = name[0, @lan.short_len + i]
      break if @kdb[re].nil? or Base64.decode64 @kdb[re].split(',')[1] != code
    end
    arg[:to_know] ? know(re, code, name) : [re, code]
  end
  def present name
    name = name.clone
    @lan.sperate.each.map {|a| name.slice! 0, a}.delete_if{|a| a.empty?}.inject {|a,b| a+'-'+b}
  end
  def remind name
    # return hex
    pya = name.split(//).map{|a| @pydb[a].force_encoding 'utf-8'}
    py = pya.inject :+
    (@lan.short_len..name.length).reverse_each do |i|
      a = @kdb[pya[0,i].inject :+]
      next unless a
      n,c,cpy,vl = a.split ','
      c = Base64.decode64 c
      vl = vl.to_i 16
      [n,cpy].each{|a| a.force_encoding 'utf-8'}
      add_var c, :valid_bits, vl
      return [n,c] if py.start_with? cpy
    end
    nil
  end
  def dename name, **arg
    arg[:as] ||= :str
    name = name.delete " -"
    name = case arg[:as]
             when :py
               raise 'pingying devide not supported, please input array of pingyings under :py kind' unless
                   name.is_a? Array
             else name.split(//).map{|a| @pydb[a]}
           end
    raise "invalid pinying found, may exists unrecorded word" if name.include? nil
    c, cl, vl, re = 0, 0, 0, ''
    re.force_encoding 'ASCII-8BIT'
    v1l = valid_bits(1)
    v1ln = 1 << v1l
    remain = @lan.words.length - v1ln
    name.each do |i|
      nw = @encodes[i]
      no_record_found unless nw
      nl = (nw >= v1ln or nw < remain) ? v1l + 1 : v1l
      c = (c << nl) | nw
      cl += nl; vl += nl
      while cl >= 8
        cl -= 8
        re << (c >> cl)
        c &= ((1<<cl)-1)
      end
    end
    re << (c << (8-cl)) if cl > 0
    add_var re, :valid_bits, vl
    re
  end
  def pylise str
    str.split(//).map{|a| @pydb[a]}.inject :+
  end

  def load_py dic
    dic.each {|k,v| @pydb[k] = v}
  end
  def check
    @lan.words.uniq{|a| @pydb[a]}.length == @lan.words.length and
        @encodes.size == @lan.words.length
  end
  def valid_bits len=nil
    len ||= @lan.max_len
    (Math.log2(@lan.words.length)*len).floor
  end

  private
  def name_bin bin
    bin.force_encoding 'ASCII-8BIT'
    v1l = valid_bits 1
    re, len, v1m, v1n = '', @lan.words.length, @lan.words.length - (1<<v1l), 1<<v1l
    ci = n1 = now = validl = 0
    loop do
      #puts "pre - #{len}, #{n1}, #{v1l+1}, #{now}"
      if n1 < v1l+1 and ci < bin.length; now = (now << 8) | bin[ci].ord; ci+=1; n1 += 8; next; end
      nc = now >> (n1 - v1l - 1)
      if n1 >= v1l + 1 and (nc < v1m or (nc >= v1n and nc < len))
        a1 = v1l + 1
      else
        a1 = [v1l, n1].min
        nc = now >> (n1 - a1)
      end
      break unless a1 > 0
      n1 -= a1; validl += a1; now &= ((1<<n1)-1)
      re << @lan.words[nc]
      break if re.length >= @lan.max_len
    end
    bin = bin[0,ci]
    add_var bin, :valid_bits, validl
    [re, bin]
  end
  def no_record_found
    raise 'pin yin query fail, found un recorded character'
  end
end

if __FILE__ == $0
begin
  dev = Zhame.new
  opts = Slop.parse do |o|
    o.banner = "The Zhame\n
give everything a name.
by Xero Essential (#{MAIL})"
    o.separator "Usage: zhame.rb action"
    o.separator ""
    o.separator "Actions:\n
  name <option>\n
  remind <name> [option] # using database to search the record,
                           if the record lost, the action will fail\n
  dename <name> # get the hexcode store in name without database,
                  for the short name, hexcode is only a part of full hash code"
    o.separator ""
    o.separator "Option for Name action:\n
Target options : \n
  you must specify no more one target"
    o.string '-f', '--file', 'path of the file'
    o.string '-s', '--string', 'a string from command line arguments'
    o.string '-t', '--text', 'read from stdin, end with EOT(^D) or any other you specified (default)', default: 'default'
    o.string '-hx', '--hex', 'a 16based string indicate the hash'
    o.separator ""
    o.separator "General options:"
    o.bool '-ms', '--machine-style', 'output under machine readable format'
    o.on '-v', '--version' do puts VERSION; exit  end
    o.bool '-h', '--help', 'output this message'
  end
  if opts[:help] or not ARGV[0]
    puts opts; exit;
  end
  case ARGV[0]
    when 'name'
      if opts[:file]
        name, code = dev.name Pathname.new opts[:file]
      elsif opts[:string]
        name, code = dev.name opts[:string]
      elsif opts[:hex]
        name, code = dev.name "#{opts[:hex]}", as: :hex
      elsif opts[:text]
        if (edc = opts[:text]) == 'default'
          edc = "\04"
          puts "input the text and ends with ^D (EOT)" unless opts[:'machine-style']
        end
        name, code = dev.name p STDIN.gets(edc)[0...-edc.length]
      else
        STDERR.puts 'invalid action'
        exit -1
      end
      puts( opts[:'machine-style'] ? "#{name}\n#{dev.short(name, code)[0]}/#{code.valid_bits}\n#{dev.present name}
#{code.unpack('H*')[0]}" :
        "Hello, I'm #{dev.present name}, \nyou can call me #{dev.present dev.short(name, code)[0]},
and my id is #{code.unpack('H*')[0]}/#{code.valid_bits}bits (you may need it?)")
    when 'remind'
      unless ARGV[1]
        STDERR.puts 'no name given'
        exit -1
      end
      name, code = dev.remind ARGV[1].delete(' -')
      unless name; STDERR.puts 'not found the name'; exit -1; end
      puts( opts[:'machine-style'] ? "#{name}\n#{code.unpack('H*')[0]}/#{code.valid_bits}" :
                "Hello, I'm #{dev.present name}, \nyou can call me #{dev.present dev.short(name, code)[0]},
and my id : #{code.unpack('H*')[0]}/#{code.valid_bits}bits")
    when 'dename'
      unless ARGV[1]
        STDERR.puts 'no name given'
        exit -1
      end
      code = dev.dename(ARGV[1])
      puts "#{code.unpack('H*')[0]}/#{code.valid_bits}bits"
    else
      puts opts
  end
rescue Exception => e
  STDERR.puts "Error merged : #{e.message}"
end
end
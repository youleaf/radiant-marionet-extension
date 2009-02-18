require 'nokogiri'
require 'net/https'

class Webservice < ActiveRecord::Base
  
  validates_presence_of :base_url, :title
  validates_uniqueness_of :title
  
  attr_reader :parameters, :data
  
  def load!(input_params = nil)
    input_params ||= {}
    @parameters ||= {}
    load_default_parameters!
    rules = YAML.load(self.rule_scheme.to_s) || []
    load_date!(input_params) if input_params[:date]
    rules.each do |param, param_rules|
      param_rules.each do |rule|
        result = rule.delete('result')
        if should_use_current_rule?(rule, input_params)
          result = substitute_variables_in_result(result, input_params)
          @parameters[param.to_sym] = result
          break
        end
      end
    end
  end
  
  
  def get_data!
    qs_params = @parameters.inject([]) do |params, values| 
      params << "#{CGI.escape(values[0].to_s)}=#{CGI.escape(values[1].to_s)}"
    end
    url = self.base_url + '?' + qs_params.join("&")
    begin
      result = ""
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")  # enable SSL/TLS
      http.start do
        http.request_get(uri.path + '?' + uri.query) { |res| result = res.body }
      end
      @data = Nokogiri::XML.parse(result)
    rescue => msg
      logger.error("\033[1;31mCan't get webservice's date: #{msg.to_s}\033[0m")
      return nil
    end
  end
  
  
  def get_value(xpath)
    @data.at(xpath, @data.root.namespaces).text.to_s if @data
  end
  
  
  private
  
    def load_default_parameters!
      parameters = YAML.load(self.default_parameters.to_s) || {}
      parameters.each { |key, value| @parameters[key.to_sym] = value }
    end
  
  
    def load_date!(input_params)
      given_date = input_params[:date]
      date = case
      when given_date == 'today'; Date.today
      when given_date == 'tomorrow'; Date.today + 1.day
      when given_date == 'yesterday'; Date.today - 1.day
      else; Date.civil(given_date[0..3].to_i, given_date[4..5].to_i, given_date[6..7].to_i)
      end
      @parameters[:date] = date.strftime("%m/%d/%Y")
    end
    
    
    def substitute_variables_in_result(result, input_params)
      result.gsub!(/:([a-zA-Z]+)/) do |s|
        input_params[$1.to_sym]
      end
      result.gsub('-', '_')
    end
    
    
    def should_use_current_rule?(rule, input_params)
      condition = true
      rule.each do |key, value|
        if value == '_any_'
          condition &&= true
        else
          condition &&= input_params[key.to_sym] == value
        end
      end
      condition
    end
  
end
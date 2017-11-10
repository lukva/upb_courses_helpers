require 'spreadsheet'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'
require 'uu_os'
require 'fileutils'
require 'highline/import'

@filename = "Makroekonomie_v16.xls"
GATEWAY = "https://uuos9.plus4u.net"

@book = nil

@access_code1 = ""
@access_code2 = ""
@tid = ""
@awid = ""

@student = ""
@test_student = ""

def get_password(prompt='Password: ')
  ask(prompt) { |q| q.echo = "*"}
end

def read_credentials()
  puts "******  uuCourseKit Bot by Unicorn College ******"
  puts "*************************************************"
  puts ""
  puts "Enter filename"
  @filename = gets.strip

  @access_code1 = get_password("Enter your access code 1 ")
  @access_code2 = get_password("Enter your access code 2 ")

  access_file = File.new("./access", "w")
  access_file.puts ("accessCode1=#{@access_code1}")
  access_file.puts ("accessCode2=#{@access_code2}")
  access_file.close

  @book = Spreadsheet.open("./#{@filename}")
end

def read_awid
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 20 && (@tid = row[1])
    index == 21 && (@awid = row[1])
  end

end

def delete_access
  File.exists?("access") && File.delete("#{File.dirname(__FILE__)}/access")
end

def read_user_groups
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 22 && (@student = "ues:#{row[1]}")
    index == 23 && (@test_student = "ues:#{row[1]}")
  end

end

def process_user_group(uri)
  UU::OS::Security::Session.login("#{File.expand_path(File.dirname(__FILE__))}/access")

  role_cast_list = UU::OS::Cast.get_access_role_cast_list(uri)

  if role_cast_list && role_cast_list.length > 0
    role_cast_list.each do |item|
      student = Hash.new
      uuid = item.casted_subject_code
      puts "Start to process #{uuid}"
      ar = UU::OS::PersonalAccessRole.get_attributes("ues:UCL-BT:#{uuid}")
      student["uuIdentity"] = uuid
      student["firstName"] = ar.first_name
      student["lastName"] = ar.surname
      student["name"] = "#{student["firstName"]} #{student["lastName"]}"
      student["state"] = uri == @test_student ? "tester" : "active"

      add_student(student.to_json)
    end
  end


  UU::OS::Security::Session.logout()
end

def post_request(uri, header, body)
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_NONE
  OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ssl_version] = "TLSv1_2"

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body

  https.request(request)
end

def grant_token
  uri = URI.parse("https://oidc.plus4u.net/uu-oidcg01-main/0-0/grantToken")
  header = {'Content-Type' => 'application/json'}
  body = {
    "accessCode1": @access_code1,
    "accessCode2": @access_code2,
    "grant_type": "password"
  }

  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_NONE
  OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ssl_version] = "TLSv1_2"

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body.to_json

  response = https.request(request)

  if response.code.to_i == 401
    puts "Invalid credentials"
    raise "Invalid credentials"
  end

  JSON.parse(response.body)["id_token"]
end

def add_student(student)
  puts "Processing student #{JSON.parse(student)["name"]}"

  header = {'Content-Type' => 'application/json', 'Authorization' => 'Bearer ' + grant_token}

  uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/addStudent")

  response = post_request(uri, header, student)

  if response.code.to_i != 200
    if JSON.parse(response.body)["uuAppErrorMap"]["uu-coursekit-course/addStudent/studentDaoCreateFailed"]
      puts "Existing user"
    else
      puts "Something went wrong", response.body, student
      raise "Something went wrong"
    end
  end
end

read_credentials
read_awid
read_user_groups
@student && process_user_group(@student)
@test_student && process_user_group(@test_student)



delete_access


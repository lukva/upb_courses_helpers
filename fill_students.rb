# encoding: UTF-8

require "rubygems"
require "uu_os"
require "csv"
require 'spreadsheet'
require 'fileutils'
require 'highline/import'

@filename = ''

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


def read_awid
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 20 && (@tid = row[1])
    index == 21 && (@awid = row[1])
  end

end

def read_user_groups
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 22 && (@student = "ues:#{row[1]}")
    index == 23 && (@test_student = "ues:#{row[1]}")
  end

end

def delete_access
  File.exists?("access") && File.delete("#{File.dirname(__FILE__)}/access")
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

def process_student_list(uri, filename)
  if File.exist?(filename)
    UU::OS::Security::Session.login("#{File.expand_path(File.dirname(__FILE__))}/access")

    open(filename) do |file|
      file.each do |line|
        uuid = line.split(",")[1]
        uuid_exists = UU::OS::Cast.exists(uri, :casted_subject_universe_id => uuid)
        UU::OS::Cast.create(uri, :casted_subject_uri => "ues:UCL-BT:#{uuid}") unless uuid_exists
        puts "#{uuid} casted to #{uri}"
      end
    end

    UU::OS::Security::Session.logout()
  end
end

read_credentials
read_awid
read_user_groups

@student && process_student_list(@student, "#{File.dirname(__FILE__)}/students.csv")
@test_student && process_student_list(@test_student, "#{File.dirname(__FILE__)}/testStudents.csv")

delete_access
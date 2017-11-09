require 'spreadsheet'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'
require 'rubygems'
require 'highline/import'

@filename = ''
TEMPLATE_UPDATE_COURSE = 'updateCourseTemplate.json'

GATEWAY = "https://uuos9.plus4u.net"

@book = nil
@template = File.open("./#{TEMPLATE_UPDATE_COURSE}", "r").read

@access_code1 = ""
@access_code2 = ""
@tid = ""
@awid = ""

def get_lsi_items(cz, en)
  lsi_cz = ""
  lsi_en = ""

  lsi_cz = "<UU5.Bricks.Lsi.Item language='cs'>#{cz}</UU5.Bricks.Lsi.Item>" if cz
  lsi_en = "<UU5.Bricks.Lsi.Item language='en'>#{en}</UU5.Bricks.Lsi.Item>" if en
  "<uu5string/><UU5.Bricks.Lsi>#{lsi_cz}#{lsi_en}</UU5.Bricks.Lsi>"
end

def get_author_items(authors)
  array = authors.split(";")

  array.map do |item|
    {
      plus4uId: clean_array(item.split(",")) ? clean_array(item.split(","))[0] : item,
      role: item.split(", ")[1] ? clean_array(item.split(","))[1] : ""
    }
  end.to_json

end

def get_languages(languages)
  array = languages.split(", ")
  array.to_json
end

def process_block_list(course_code)
  sheet = @book.worksheet("Structure")
  block_list = []
  block_root = 0
  topic_root = 0
  lesson_root = 0
  level = ""
  block = Hash.new
  topic = Hash.new
  lesson = Hash.new
  block_added_to_root = false
  topic_added_to_block = false
  lesson_added_to_topic = false
  code = ""

  sheet.each_with_index do |row, index|
    if row[0][0,1] == "$" # ridici znak
      level = row[0][1..-1].split("_")[0]
      code = row[0][1..-1].split("_")[1]

      if level == "BLOCK"
        topic && topic.length > 0 && block[:topicList].push(topic)
        block && block.length > 0 && block_list.push(block)
        block = {topicList: []}
        topic = {}
        block_added_to_root = false
        block_root = index

      end
      if level == "TOPIC"
        topic && topic.length > 0 && block[:topicList].push(topic)
        topic = {lessonCodeList: []}
        topic_added_to_block = false
        topic_root = index
      end
      if level == "LESSON"
        topic[:lessonCodeList].push("#{course_code}_#{code}")
        lesson && lesson.length > 0 && upload_lesson(lesson.to_json)
        lesson = {}
        lesson = {questionCodeList: []}
        lesson_added_to_topic = false
        lesson_root = index
      end
    end

    if level == "BLOCK"
      (index == block_root) && (block[:code] = "#{course_code}_#{code}")
      (index == block_root + 1) && (block[:name] = get_lsi_items(row[1],row[2]))
      (index == block_root + 2) && (block[:checkpoint] = row[1] ? row[1] : nil)
    end

    if level == "TOPIC"
      (index == topic_root) && (topic[:code] = "#{course_code}_#{code}")
      (index == topic_root + 1) && (topic[:name] = get_lsi_items(row[1],row[2]))
      (index == topic_root + 2) && (topic[:image] = row[1] ? row[1] : nil)
    end

    if level == "LESSON"
      (index == lesson_root) && (lesson[:code] = "#{course_code}_#{code}")
      (index == lesson_root + 1) && (lesson[:name] = get_lsi_items(row[1],row[2]))
      (index == lesson_root + 2) && (lesson[:desc] = get_lsi_items(row[1],row[2]))
      (index == lesson_root + 3) && (lesson[:state] = row[1] ? row[1] : "null")
      if index == (lesson_root + 4)
        if row[1]
          question_code_list = clean_array(row[1].split(","))
          question_code_list = question_code_list.map do |item|
            item["$"] = "#{course_code}_"
            item
          end
        end
        lesson[:questionCodeList] = row[1] ? question_code_list : nil
      end
      (index == lesson_root + 5) && (lesson[:minScoreToPass] = row[1] ? row[1].to_i : "null")
      (index == lesson_root + 6) && (lesson[:minScoreToFullStar] = row[1] ? row[1].to_i : "null")
      (index == lesson_root + 7) && (lesson[:image] = row[1] ? row[1] : "null")
    end

  end

  !lesson_added_to_topic && upload_lesson(lesson.to_json)
  !topic_added_to_block && block[:topicList].push(topic)
  !block_added_to_root && block_list.push(block)
  block_list.to_json
end

def clean_array(array)
  array.map do |item|
    item.delete(' ')
  end
end

def post_request(uri, header, body)
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body

  https.request(request)
end

def upload_lesson(lesson)
  puts "Processing lesson #{JSON.parse(lesson)["code"]}"
  add = "addLesson"
  update = "updateLesson"

  header = {'Content-Type' => 'application/json', 'Authorization' => 'Bearer ' + grant_token}

  uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/#{add}")

  response = post_request(uri, header, lesson)

  if JSON.parse(response.body)["uuAppErrorMap"]["uu-coursekit-course/addLesson/lessonDaoCreateFailed"]
    uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/#{update}")
    response = post_request(uri, header, lesson)
  end

  unless response.code.to_i == 200
    puts "Something went wrong", response.body
    raise "Something went wrong"
  end

end

def read_awid
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 20 && (@tid = row[1])
    index == 21 && (@awid = row[1])
  end

end

def process_content
  sheet = @book.worksheet("Course")

  course_code = ""
  course_name = ""
  title_cs = ""
  title_en = ""
  course_desc = ""
  course_intro = ""
  leading_authors = ""
  other_authors = ""
  state = ""
  languages = ""
  expiration = 0
  shortcut = "ne"
  prerequisite = ""
  scan = ""
  question_number = 0
  duration = 0
  min_score_to_pass = 0
  min_score_to_full_stars = 0
  max_stars = 0
  course_menu_size = "big"
  topic_menu_size = "big"
  logo = ""

  sheet.each_with_index do |row, index|
    index == 0 && (course_code = row[0])
    index == 1 && (course_name = get_lsi_items(row[1], row[2]))
    if index == 2
      title_cs = row[1]
      title_en = row[2]
    end
    index == 3 && (course_desc = get_lsi_items(row[1], row[2]))
    index == 4 && (course_intro = get_lsi_items(row[1], row[2]))
    index == 5 && row[1] && (leading_authors = get_author_items(row[1]))
    index == 6 && row[1] && (other_authors = get_author_items(row[1]))
    index == 7 && (languages = get_languages(row[1]))
    index == 8 && (state = row[1])
    index == 9 && (prerequisite = row[1])
    index == 10 && (expiration = row[1])
    index == 11 && (shortcut = row[1])
    index == 12 && (scan = row[1])
    index == 13 && (question_number = row[1])
    index == 14 && (duration = row[1])
    index == 15 && (min_score_to_pass = row[1])
    index == 16 && (min_score_to_full_stars = row[1])
    index == 17 && (max_stars = row[1])
    index == 18 && (course_menu_size = row[1])
    index == 19 && (topic_menu_size = row[1])
    index == 24 && (logo = row[1])
  end

  @template["_COURSE_CODE_"] = course_code
  @template["_COURSE_NAME_"] = course_name
  @template["_TITLE_CS_"] = title_cs == "" ? nil : '"' + title_cs + '"'
  @template["_TITLE_EN_"] = title_en == "" ? nil : '"' + title_en + '"'
  @template["_DESC_"] = course_desc
  @template["_INTRO_"] = course_intro
  @template["_STATE_"] = state
  @template["_LANGUAGE_"] = languages
  @template["_SHORTCUT_"] = shortcut == "ne" ? "false" : "true"
  @template["_EXPIRATION_"] = expiration ? expiration.to_i.to_s : "null"
  @template["_PREREQUISITE_TEST_"] = prerequisite ? prerequisite : "null"
  @template["_SCAN_TEST_"] = scan ? scan : "null"
  @template["_QUESTION_NUMBER_"] = question_number ? question_number.to_i.to_s : "null"
  @template["_MAX_DURATION_"] = duration ? duration.to_i.to_s : "null"
  @template["_MIN_SCORE_TO_PASS_"] = min_score_to_pass ? min_score_to_pass.to_i.to_s : "null"
  @template["_MIN_SCORE_TO_FULL_STAR_"] = min_score_to_full_stars ? min_score_to_full_stars.to_i.to_s : "null"
  @template["_MAX_STARS_"] = max_stars ? max_stars.to_i.to_s : "null"
  @template["_BLOCK_LIST_"] = process_block_list(course_code)
  @template["_COURSE_MENU_SIZE_"] = course_menu_size
  @template["_TOPIC_MENU_SIZE_"] = topic_menu_size
  @template["_LOGO_"] = logo

  puts @template

  @template
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

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body.to_json

  response = https.request(request)

  if response.code.to_i == 401
    puts "Invalid credentials"
    raise "Invalid credentials"
  end

  JSON.parse(response.body)["id_token"]
end

def update_course(body)
  uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/updateCourse")

  header = {'Content-Type' => 'application/json', 'Authorization' => 'Bearer ' + grant_token}

  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body

  response = https.request(request)

  unless response.code.to_i == 200
    puts "Something went wrong", response.body
    raise "Something went wrong"
  end

end

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

  @book = Spreadsheet.open("#{File.expand_path(File.dirname(__FILE__))}/#{@filename}")
end

read_credentials
read_awid
content = process_content
update_course(content)

puts content
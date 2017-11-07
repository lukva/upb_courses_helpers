require 'spreadsheet'
require 'json'
require 'net/http'
require 'uri'
require 'rubygems'
require 'highline/import'

@filename = 'EHT_v5.xls'

GATEWAY = "https://uuos9.plus4u.net"

@access_code1 = ""
@access_code2 = ""

@tid = ""
@awid = ""

@book = Spreadsheet.open("./#{@filename}")

def get_lsi_items(cz, en)
  lsi_cz = ""
  lsi_en = ""
  lsi_cz = "<UU5.Bricks.Lsi.Item language='cs'>#{cz}</UU5.Bricks.Lsi.Item>" if cz
  lsi_en = "<UU5.Bricks.Lsi.Item language='en'>#{en}</UU5.Bricks.Lsi.Item>" if en
  "<uu5string/><UU5.Bricks.Lsi>#{lsi_cz}#{lsi_en}</UU5.Bricks.Lsi>"
end

def get_languages(languages)
  array = languages.split(", ")
  array.to_json
end

def process_sheet(type, course_code, sheet)
  question_root = 0
  code = ""
  question = Hash.new
  question_added_to_root = false

  sheet.each_with_index do |row, index|
    if row[0][0,1] == "$" # ridici znak
      code = row[0][1..-1].split("_")[1]
      question && question.length > 0 && upload_question(question.to_json)
      question = Hash.new
      question[:correctAnswerIndexList] = []
      question_added_to_root = false
      question_root = index
    end

    (index == question_root) && (question[:code] = "#{course_code}_#{type}_#{code}")
    if index == (question_root + 1)
      question[:type] = type
      question[:task] = get_lsi_items(row[1],row[2])
      question[:answerList] = []
    end
    if index == (question_root + 2)
      row[1] && question[:answerList].push(get_lsi_items(row[1],row[2]))
      if type == "T03"
        row[3] == "x" && question[:correctAnswerIndexList].push(0)
      else
        row[3] && (question[:correctAnswerIndex] = 0)
      end

    end
    if index == (question_root + 3)
      row[1] && question[:answerList].push(get_lsi_items(row[1],row[2]))
      if type == "T03"
        row[3] == "x" && question[:correctAnswerIndexList].push(1)
      else
        row[3] && (question[:correctAnswerIndex] = 1)
      end
    end
    if index == (question_root + 4)
      row[1] && question[:answerList].push(get_lsi_items(row[1],row[2]))
      if type == "T03"
        row[3] == "x" && question[:correctAnswerIndexList].push(2)
      else
        row[3] && (question[:correctAnswerIndex] = 2)
      end
    end
    if index == (question_root + 5)
      row[1] && question[:answerList].push(get_lsi_items(row[1],row[2]))
      if type == "T03"
        row[3] == "x" && question[:correctAnswerIndexList].push(3)
      else
        row[3] && (question[:correctAnswerIndex] = 3)
      end
    end
    if index == (question_root + 6)
      row[1] && question[:answerList].push(get_lsi_items(row[1],row[2]))
      if type == "T03"
        row[3] == "x" && question[:correctAnswerIndexList].push(4)
      else
        row[3] && (question[:correctAnswerIndex] = 4)
      end
    end
    (index == question_root + 7) && (question[:instruction] = get_lsi_items(row[1],row[2]))
    (index == question_root + 8) && (question[:successFeedbackText] = get_lsi_items(row[1],row[2]))
    (index == question_root + 9) && (question[:errorFeedbackText] = get_lsi_items(row[1],row[2]))
    (index == question_root + 10) && (question[:resultFeedbackText] = get_lsi_items(row[1],row[2]))
    (index == question_root + 11) && (question[:timeLimit] = row[1] ? row[1].to_i : 60)
    (index == question_root + 12) && (question[:answerRandom] = row[1] == "ano")
    (index == question_root + 13) && (question[:state] = row[1])
    (index == question_root + 14) && (question[:image] = row[1])

  end

  !question_added_to_root && upload_question(question.to_json)
end

def clean_array(array)
  array.map do |item|
    item.delete(' ')
  end
end

def post_request(uri, header, body)
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body

  https.request(request)
end

def upload_question(question)
  puts "Processing question #{JSON.parse(question)["code"]}"
  add = "addQuestion"
  update = "updateQuestion"

  header = {'Content-Type' => 'application/json', 'Authorization' => 'Bearer ' + grant_token}

  uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/#{add}")

  response = post_request(uri, header, question)
  puts question

  if JSON.parse(response.body)["uuAppErrorMap"]["uu-coursekit-course/addQuestion/questionDaoCreateFailed"]
    uri = URI.parse("#{GATEWAY}/uu-coursekitg01-course/#{@tid}-#{@awid}/#{update}")
    response = post_request(uri, header, question)
  end

  unless response.code.to_i == 200
    puts "Something went wrong", response.body, question
    raise "Something went wrong"
  end
end

def process_questions
  sheet = @book.worksheet("Course")
  course_code = ""
  sheet.each_with_index do |row, index|
    course_code = row[0] if index == 0
  end

  sheet_01 = @book.worksheet("Questions_T01")
  process_sheet("T01", course_code, sheet_01) if sheet_01

  sheet_02 = @book.worksheet("Questions_T02")
  process_sheet("T02", course_code, sheet_02) if sheet_02

  sheet_03 = @book.worksheet("Questions_T03")
  process_sheet("T03", course_code, sheet_03) if sheet_03

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

  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body.to_json

  response = https.request(request)

  if response.code.to_i == 401
    puts "Invalid credentials"
    raise "Invalid credentials"
  end

  JSON.parse(response.body)["id_token"]
end

def get_password(prompt='Password: ')
  ask(prompt) { |q| q.echo = false}
end

def read_awid
  sheet = @book.worksheet("Course")

  sheet.each_with_index do |row, index|
    index == 20 && (@tid = row[1])
    index == 21 && (@awid = row[1])
  end

end


def read_credentials()
  puts "******  uuCourseKit Bot by Unicorn College ******"
  puts "*************************************************"
  puts ""
  puts "Enter filename"
  @filename = gets

  @access_code1 = get_password("Enter your access code 1 ")
  @access_code2 = get_password("Enter your access code 2 ")
end

read_credentials
read_awid
process_questions



# encoding: utf-8
require "logstash/codecs/base"

class LogStash::Codecs::Ansi < LogStash::Codecs::Base
  config_name "ansi"

  config :columns, :validate => :number, :default => 0
  config :indent, :validate => :number, :default => 4
  config :fields, :validate => :array, :default => ["message"]
  config :highlighters, :validate => :array

  public
  def register
    @colors = {
      "Black" => "0",
      "Red" => "1",
      "Green" => "2",
      "Yellow" => "3",
      "Blue" => "4",
      "Magenta" => "5",
      "Cyan" => "6",
      "White" => "7",
      "Default" => "9"
    }

    if @columns <= 0 then
      @columns = detect_terminal_width
      if @columns <= 0 then
        @columns = 80
      end
    end

    @lineIndent = ""
    while @lineIndent.length <= @indent do
      @lineIndent << " "
    end

    @highlighters.each do |highlighter|
      highlighter["pattern"] = Regexp.new highlighter["match"]
    end

    @fields.each do |definition|
      if definition["highlighters"] then
        definition["highlighters"].each do |highlighter|
          highlighter["pattern"] = Regexp.new highlighter["match"]
          highlighter["replacement"] = ""
          set_highlighter highlighter["replacement"], highlighter
          highlighter["replacement"] << '\0'
        end
      end
    end

  end # def register

  public
  def decode(data)
    raise "Not implemented"
  end # def decode

  public
  def encode(event)

    line_highlighter = { "background" => "Default", "foreground" => "Default", "bold" => "false" }

    message = ""
    @highlighters.each do |highlighter|

      value = event[highlighter["field"]]
      if value =~ highlighter["pattern"] then
        line_highlighter = highlighter
        break
      end
    end

    set_highlighter message, line_highlighter

    # Render fields
    isFirst = true
    @fields.each do |definition|
      if !isFirst then
        message << " "
      else
        isFirst = false
      end

      value = event[definition["field"]]
      if definition["formatter"] then
        value = (value.instance_eval definition["formatter"])
      end

      if definition["highlighters"] then
        definition["highlighters"].each do |highlighter|
          replacement = highlighter["replacement"]
          set_highlighter replacement, line_highlighter
          value = value.gsub highlighter["pattern"], replacement
        end
      end

      message << value.to_s

      set_highlighter message, line_highlighter
    end

    # Wrap and indent lines
    currentIndex = 0
    cnt = 0
    wrap_index = 0
    while currentIndex < message.length do

      if cnt == @columns then
        if currentIndex - wrap_index > @columns / 2 then
          message.insert currentIndex, @lineIndent
          cnt = @lineIndent.length
        else
          message.insert wrap_index, "\n"
          message.insert wrap_index + 1, @lineIndent
          cnt = @lineIndent.length + (currentIndex - wrap_index)
        end

        currentIndex += @lineIndent.length
        wrap_index = 0
      end

      chr = message[currentIndex]

      if chr == " " || chr == "_" then
        wrap_index = currentIndex + 1
      end

      if chr == "\r" then
        # ignore
      elsif chr == "\n" then
        message.insert currentIndex + 1, @lineIndent
        currentIndex += @lineIndent.length + 1
        cnt = @lineIndent.length + 1
      elsif chr == "\x1B" then
        while currentIndex < message.length do
          chr = message[currentIndex]

          if chr == "m" then
            break
          end
          currentIndex += 1
        end
      else
        cnt += 1
      end

      currentIndex += 1
    end

    if cnt < @columns then
      message << "\n"
    end

    # Publish message
    @on_event.call(event, message)
  end # def encode

  def set_highlighter(message, highlighter)
    message << "\x1B["
    if highlighter["bold"] == "true" then
      message << "1"
    else
      message << "0"
    end
    if highlighter["foreground"] then
      message << ";3"
      message << @colors[highlighter["foreground"]]
    end
    if highlighter["background"] then
      message << ";4"
      message << @colors[highlighter["background"]]
    end
    message << "m"
  end

  def detect_terminal_width
    if (ENV['COLUMNS'] =~ /^\d+$/) then
      return ENV['COLUMNS'].to_i
    end

    conResult = `mode con`.scan(/Columns:\s*(\d+)/)
    if conResult.length > 0 then
      width = conResult[0][0].to_i
      if width > 0 then
        return width
      end
    end

    width = `tput cols`.to_i
    if width > 0 then
      return width
    end

    width = (`stty size`.scan(/\d+/).map { |s| s.to_i }.reverse)[0]
    return width
  rescue
    return 0
  end

end # class LogStash::Codecs::Dots

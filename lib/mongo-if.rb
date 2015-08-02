module MongoIF # Mongo Interactive Fiction
  class PageTokenizer
    attr_reader :tokens

    def initialize(page_contents)
      @page_contents = page_contents
      @tokens = []

      extract_tokens
    end

    def extract_tokens
      @page_contents.lines do |line|
        tokenizer = LineTokenizer.new(line)
        @tokens.concat(tokenizer.tokens)
      end
    end
  end

  class LineTokenizer
    attr_reader :tokens

    def initialize(line)
      @line = line.strip
      @tokens = []

      @inside_link = false
      @inside_link_path = false
      @link_text = nil

      extract_tokens
    end

    private

    def extract_tokens
      if @line =~ /^\s*$/
        @tokens << Token.new(text: "<p></p>", degrades: false)
        return
      end

      parts = @line.split(/(\]\]|\[\[|\|)/)

      parts.each do |part|
        case part
        when "[["
          @inside_link = true
          @inside_link_path = false
          @link_text = nil
        when "|"
          @inside_link_path = true
        when "]]"
          @inside_link = false
          @inside_link_path = false
          @link_text = nil
        else
          if @inside_link
            if @inside_link_path
              links_to = part
              links_to.gsub!(' ', '_')
              @tokens << Token.new(text: @link_text, links_to: links_to, degrades: false)
            else
              @link_text = part
            end
          else
            @tokens << Token.new(text: part, degrades: true)
          end
        end
      end
    end
  end

  class Page
    include Mongoid::Document

    field :identifier, type: String
    field :title, type: String

    embeds_many :tokens

    index({ identifier: 1 }, { unique: true })

    def self.from_file(filepath)
      page_name = File.basename(filepath, File.extname(filepath))

      page_contents = File.read(filepath)

      tokens = PageTokenizer.new(page_contents).tokens

      page = Page.new(identifier: page_name, title: page_name, tokens: tokens)
    end

    def degrade!
      self.tokens = self.tokens.map(&:degraded)
      save
    end

    def render
      self.tokens.map(&:render).join('')
    end
  end

  class Token
    include Mongoid::Document

    field :text, type: String
    field :links_to, type: String
    field :degrades, type: Boolean

    embedded_in :page

    def render
      if links_to
        "<a href=\"/#{links_to}\">#{text}</a>"
      else
        text
      end
    end

    def degraded
      return self unless degrades

      undegraded_char_indices = []

      degraded_text = text.to_str

      degraded_text.split('').each_with_index do |character, index|
        undegraded_char_indices << index if character =~ /[a-zA-Z]/
      end

      return self if undegraded_char_indices.length == 0

      char_to_degrade = undegraded_char_indices[rand(0...undegraded_char_indices.length)]

      degraded_text[char_to_degrade] = '_'

      Token.new(text: degraded_text, links_to: links_to, degrades: degrades)
    end
  end
end

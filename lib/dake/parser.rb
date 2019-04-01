require 'parslet'

class DakeParser < Parslet::Parser
  # Single character rules
  rule(:lparen)                 { str('(') >> space.maybe }
  rule(:rparen)                 { space.maybe >> str(')') }
  rule(:lsbracket)              { str('[') >> space.maybe }
  rule(:rsbracket)              { space.maybe >> str(']') }
  rule(:lcbracket)              { str('{') >> space.maybe }
  rule(:rcbracket)              { str('}') >> space.maybe }
  rule(:back_slash)             { str('\\') }
  rule(:dollar_sign)            { str('$') }
  rule(:single_quote)           { str('\'') }
  rule(:double_quote)           { str('"') }
  rule(:colon)                  { str(':') }
  rule(:semicolon)              { str(';') }
  rule(:comma)                  { space.maybe >> str(',') >> space.maybe }
  rule(:equal_sign)             { space.maybe >> str('=') >> space.maybe }
  rule(:meta_char)              { match('[<>|?*\[\]$\\\(){}"\'`&;=#,%!@]') }

  # Things
  rule(:indentation)            { match('[ \t]').repeat(1) }
  rule(:space)                  { (match('[ \t]') | (back_slash >> lbr)).repeat(1) }
  rule(:dos_newline)            { str("\r\n") }
  rule(:unix_newline)           { str("\n") }
  rule(:mac_newline)            { str("\r") }
  rule(:lbr)                    { dos_newline | unix_newline | mac_newline }
  rule(:eol)                    { lbr | any.absent? }
  rule(:left_arrow)             { space.maybe >> str('<-') >> space.maybe }
  rule(:or_equals)              { space.maybe >> str('|=') >> space.maybe }
  rule(:escaped_back_slash)     { str('\\\\') }
  rule(:escaped_single_quote)   { str('\\\'') }
  rule(:escaped_char) do
    back_slash >>
      (str('x') >> match('[0-9a-fA-F]').repeat(1, 2).as(:hex_char)     |
       str('u') >> match('[0-9a-fA-F]').repeat(1, 4).as(:unicode_char) |
       match('[abtnvfre\\\'"]').as(:ctrl_char)                         |
       any.as(:norm_char)).as(:escaped_char)
  end

  # Grammar parts
  rule(:comment)      { str('#') >> (lbr.absent? >> any).repeat(1).as(:chars).maybe }
  rule(:comment_line) { comment >> eol }
  rule(:identifier)   { match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat }

  rule(:string) do
    (single_quote >>
      (escaped_single_quote.as(:single_quote) |
       escaped_back_slash.as(:back_slash)     |
       ((escaped_single_quote |
         escaped_back_slash   |
         single_quote).absent? >> any).repeat(1).as(:chars)).repeat.as(:text) >>
    single_quote) |
    (double_quote >>
      (variable_substitution |
       command_substitution  |
       escaped_char          |
       ((variable_substitution |
         command_substitution  |
         escaped_char          |
         double_quote).absent? >> any).repeat(1).as(:chars)).repeat.as(:text) >>
    double_quote)
  end

  rule(:text_value) do
    string |
    (variable_substitution |
     command_substitution  |
     ((variable_substitution |
       command_substitution  |
       space                 |
       meta_char             |
       lbr).absent? >> any).repeat(1).as(:chars)).repeat(1).as(:text)
  end

  rule(:variable_substitution) do
    dollar_sign >> lsbracket >> identifier.as(:var_sub) >> rsbracket
  end

  rule(:command_substitution) do
    dollar_sign >> lparen >>
      (variable_substitution |
       escaped_char |
       ((variable_substitution | escaped_char | rparen).absent? >> any).repeat(1).as(:chars)).repeat(1).as(:cmd_sub) >> rparen
  end

  rule(:variable_assignment) do
    identifier.as(:var_name) >>
    equal_sign >>
    text_value.as(:var_value) >> space.maybe >> comment.maybe >> eol
  end

  rule(:variable_definition) do
    identifier.as(:var_name) >>
    or_equals >>
    text_value.as(:var_value) >> space.maybe >> comment.maybe >> eol
  end

  rule(:include_directive) do
    str('%include') >> space >> text_value >> space.maybe >> comment.maybe >> eol
  end

  rule(:call_directive) do
    str('%call') >> space >> text_value >> space.maybe >> comment.maybe >> eol
  end

  rule(:context_directive) do
    str('%context') >> space >> text_value >> space.maybe >> comment.maybe >> eol
  end

  rule(:file_list) do
    (str('@') >> str('^').maybe.as(:regex) >> text_value.as(:tag_name) |
        match('[!?]').maybe.as(:flag) >> str('^').maybe.as(:regex) >> text_value.as(:file_name)).repeat(1, 1) >>
    (comma >> (str('@') >> str('^').maybe.as(:regex) >> text_value.as(:tag_name) |
        match('[!?]').maybe.as(:flag) >> str('^').maybe.as(:regex) >> text_value.as(:file_name))).repeat
  end

  rule(:option) do
    (match('[+-]').as(:flag_state) >> identifier.as(:flag_name))           |
    (identifier.as(:option_name) >> colon >> text_value.as(:option_value)) |
    identifier.as(:protocol)
  end

  rule(:option_list) do
    lsbracket >>
    option.repeat(1, 1) >>
    (space >> option).repeat >> space.maybe >>
    rsbracket
  end

  rule(:step) do
    step_definition.as(:step_def) >> comment_line.repeat.as(:doc_str) >> command_body.repeat(0, 1).as(:step_cmd)
  end

  rule(:step_definition) do
    file_list.as(:output_files) >>
    left_arrow >>
    file_list.repeat(0, 1).as(:input_files) >> space.maybe >>
    option_list.repeat(0, 1).as(:option_list) >> space.maybe >> comment.maybe >> eol
  end

  rule(:command_text) do
    (variable_substitution |
     ((variable_substitution | lbr).absent? >> any).repeat(1).as(:chars)).repeat.as(:text)
  end

  rule(:command_body) do
    command_line.repeat(1) >> (command_line | lbr).repeat
  end

  rule(:command_line) do
    indentation.as(:indent) >> command_text.as(:cmd_text) >> eol
  end

  rule(:step_method) do
    method_definition >> comment_line.repeat.as(:doc_str) >> command_body.as(:method_cmd)
  end

  rule(:method_definition) do
    identifier.as(:method_name) >> lparen >> rparen >> space.maybe >>
    option_list.maybe.as(:option_list) >> space.maybe >> comment.maybe >> eol
  end

  rule(:ifeq_condition) do
    text_value.as(:ifeq_left) >>
    comma >>
    text_value.as(:ifeq_right) >> space.maybe >> comment.maybe >> eol
  end

  rule(:ifdef_condition) do
    identifier.as(:ifdef_var) >> space.maybe >> comment.maybe >> eol
  end

  rule(:conditional_directive) do
    ((str('%ifeq')   >> space >> ifeq_condition).as(:ifeq)   |
     (str('%ifneq')  >> space >> ifeq_condition).as(:ifneq)  |
     (str('%ifdef')  >> space >> ifdef_condition).as(:ifdef) |
     (str('%ifndef') >> space >> ifdef_condition).as(:ifndef)) >>
    workflow.as(:if_body) >>
    (str('%else') >> space.maybe >> eol >>
     workflow).maybe.as(:else_body) >>
    str('%endif') >> space.maybe >> comment.maybe >> eol
  end

  rule(:scope) do
    lcbracket >> space.maybe >> comment.maybe >> eol >>
    workflow >>
    rcbracket >> space.maybe >> comment.maybe >> eol
  end

  rule(:workflow) do
    (comment_line.as(:comment_line)          |
     variable_assignment.as(:var_assignment) |
     variable_definition.as(:var_definition) |
     include_directive.as(:include)          |
     call_directive.as(:call)                |
     context_directive.as(:context)          |
     conditional_directive                   |
     step_method                             |
     step                                    |
     scope                                   |
     lbr).repeat.as(:workflow)
  end
  root :workflow
end

Chars       = Struct.new(:string)
Text        = Struct.new(:items)
VariableDef = Struct.new(:var_name, :var_value, :type, :src_file)
VariableSub = Struct.new(:var_name)
CommandSub  = Struct.new(:cmd_text)
Target      = Struct.new(:name, :scheme, :tag, :flag, :regex)
Option      = Struct.new(:name, :value)
EqCond      = Struct.new(:eq_lhs, :eq_rhs)
DefCond     = Struct.new(:var_name)
Workflow    = Struct.new(:tasks, :src_file)
Condition   = Struct.new(:cond, :not, :if_body, :else_body)
Inclusion   = Struct.new(:files, :type, :src_file)
Step        = Struct.new(:targets, :prerequisites, :options, :option_dict, :commands,
                         :cmd_text, :context, :src_file, :doc_str) { def hash; self.object_id.hash end }
StepMethod  = Struct.new(:name, :options, :option_dict, :commands,
                         :cmd_text, :context, :src_file, :doc_str)

class DakeTransform < Parslet::Transform
  UNESCAPES = { 'a' => "\x07", 'b' => "\x08", 't'    => "\x09", 'n'  => "\x0a", 'v' => "\x0b", 'f' => "\x0c",
                'r' => "\x0d", 'e' => "\x1b", "\\\\" => "\x5c", "\"" => "\x22", "'" => "\x27" }
  rule(single_quote: simple(:x))     { '\'' }
  rule(back_slash: simple(:x))       { '\\' }
  rule(unicode_char: simple(:c))     { [c.to_s.hex].pack('U') }
  rule(hex_char: simple(:c))         { [c.to_s.hex].pack('C') }
  rule(oct_char: simple(:c))         { [c.to_s.oct].pack('C') }
  rule(ctrl_char: simple(:c))        { UNESCAPES[c.to_s] }
  rule(norm_char: simple(:c))        { c }
  rule(escaped_char: simple(:c))     { c }
  rule(chars: simple(:c))            { Chars.new(c) }
  rule(text: sequence(:s))           { Text.new(s) }
  rule(comment_line: simple(:c))     { nil }
  rule(cmd_sub: sequence(:t))        { CommandSub.new(Text.new(t)) }
  rule(var_assignment: sequence(:s)) { |env| VariableDef.new(env[:s][0], env[:s][1], :assign, env[:src_file]) }
  rule(var_definition: sequence(:s)) { |env| VariableDef.new(env[:s][0], env[:s][1], :define, env[:src_file]) }
  rule(var_sub: simple(:n))          { VariableSub.new(n) }
  rule(ifdef_var: simple(:c))        { DefCond.new(c) }
  rule(include: simple(:f))          { |env| Inclusion.new(env[:f], :include, env[:src_file]) }
  rule(call: simple(:f))             { |env| Inclusion.new(env[:f], :call, env[:src_file]) }
  rule(context: simple(:f))          { |env| Inclusion.new(env[:f], :context, env[:src_file]) }
  rule(workflow: sequence(:s))       { |env| Workflow.new(env[:s].compact, env[:src_file]) }

  rule(var_name: simple(:name),
       var_value: simple(:value))    { [name, value] }

  rule(tag_name: simple(:t),
       regex: simple(:r))            { Target.new(t, nil, true, nil, (r.nil? ? nil : r.to_s)) }

  rule(file_name: simple(:f),
       flag: simple(:o),
       regex: simple(:r))            { Target.new(f, nil, false, (o.nil? ? nil : o.to_s), (r.nil? ? nil : r.to_s)) }

  rule(protocol: simple(:s))         { Option.new('protocol', s) }

  rule(flag_name: simple(:f),
       flag_state: simple(:s))       { Option.new(f, s) }

  rule(option_name: simple(:k),
       option_value: simple(:v))     { Option.new(k, v) }

  rule(input_files: sequence(:if),
       output_files: sequence(:of),
       option_list: sequence(:opt))  { |env| Step.new(env[:of], env[:if], env[:opt], nil, [], nil, nil, env[:src_file], nil) }

  rule(indent: simple(:i),
       cmd_text: simple(:t))         { t.items.unshift i; t }

  rule(step_def: simple(:s),
       doc_str: sequence(:d),
       step_cmd: sequence(:c))       { s.doc_str = d; c.each { |c| s.commands << c }; s }

  rule(method_name: simple(:s),
       option_list: sequence(:o),
       doc_str: sequence(:d),
       method_cmd: sequence(:c))     { |env| StepMethod.new(env[:s], env[:o], nil, env[:c], nil, nil, env[:src_file], env[:d]) }

  rule(ifeq_left: simple(:l),
       ifeq_right: simple(:r))       { EqCond.new(l, r) }

  rule(ifeq: simple(:c),
       if_body: simple(:i),
       else_body: simple(:e))        { Condition.new(c, false, i, e) }

  rule(ifneq: simple(:c),
       if_body: simple(:i),
       else_body: simple(:e))        { Condition.new(c, true, i, e) }

  rule(ifdef: simple(:c),
       if_body: simple(:i),
       else_body: simple(:e))        { Condition.new(c, false, i, e) }

  rule(ifndef: simple(:c),
       if_body: simple(:i),
       else_body: simple(:e))        { Condition.new(c, true, i, e) }
end
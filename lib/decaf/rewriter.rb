require 'parser/current'
require 'pry'

module Decaf
  class Rewriter < Parser::TreeRewriter
    def on_send(node)
      if node.children.any? { |c| c == :then }
        return # don't process
      elsif node.children.any? { |c| c == :stubs }
        process_stubs(node)
      elsif node.children.any? { |c| c == :stub }
        process_stub(node)
      elsif node.children.any? { |c| c == :mock }
        process_mock(node)
      elsif node.children.any? { |c| c == :expects }
        process_expects(node)
      elsif node.children.any? { |c| c == :returns }
        return if node.children.any? { |c| c.to_s.match ':then' }
        process_returns(node)
      elsif node.children.any? { |c| c == :with }
        process_with(node) || super
      elsif node.children.any? { |c| c == :never }
        process_never(node) || super
      elsif node.children.any? { |c| c == :raises }
        process_raises(node)
      else
        super
      end
    end

    def on_stubs(node)
      left_expr, rest, expectation = *node
      parens = !!node.location.begin
      multiline = (node.location.begin&.line || 0) != (node.location.end&.line || 0)
      if multiline
        replace(node.location.begin, " {") if node.location.begin
        replace(node.location.end, "  }") if node.location.end
      else
        remove(node.location.begin) if node.location.begin
        remove(node.location.end) if node.location.end
      end
      left_expr = Parser::AST::Node.new(
        expectation, [left_expr], location: left_expr.location
      )
      receive = Parser::AST::Node.new(
        :receive, [node.loc.selector, parens, multiline, rest], location: rest.location
      )
      node.updated(nil, [process(left_expr), process(receive)])
    end

    def on_allow(node)
      wrap(node.location.expression, "allow(", ")")
    end

    def on_allow_any(node)
      wrap(node.location.expression, "allow_any_instance_of(", ")")
    end

    def on_receive(node)
      after, parens, multiline, left, expectation = *node
      pairs = *left
      receive_expectation = if pairs.length > 1
        "receive_messages"
      else
        "receive"
      end
      receive_method, returns = parse_receive_method(left)
      to_receive = if expectation == :not
                     "to_not #{receive_expectation}(#{receive_method})"
                   else
                     "to #{receive_expectation}(#{receive_method})"
                   end
      remove(left.location.expression)
      insert_after(after, to_receive)
      if returns
        expression = convert_source_to_double(returns.loc.expression.source)
        returns_source = if multiline
          "  #{expression}"
        else
          "#{" " if parens}{ #{expression} }"
        end
        replace(left.location.expression, returns_source)
      else
        node.updated(nil, left)
      end
    end

    def on_expects(node)
      left, right, expectation = *node
      parens = !!node.location.begin
      remove(node.location.begin) if node.location.begin
      remove(node.location.end) if node.location.end
      expect = Parser::AST::Node.new(
        :expect, left, location: left.location
      )
      receive = Parser::AST::Node.new(
        :receive, [node.loc.selector, parens, false, right, expectation],
        location: right.location
      )
      node.updated(nil, [process(expect), process(receive)])
    end

    def on_with(node)
      left_expr, *with, expectation = *node
      expect, var, receive = *left_expr
      first, last = *with
      remove(left_expr.location.selector)
      insert_before(with.first.loc.expression, ".with(")
      insert_after(with.last.loc.expression, ")")
      new_node = Parser::AST::Node.new(
        :expects, [expect, receive, expectation], location: left_expr.location
      )
      node.updated(nil, [process(new_node), *with])
    end

    def on_expect(node)
      wrap(node.location.expression, "expect(", ")")
    end

    private

    def process_stubs(node)
      left_expr, _variable_name, rest = *node
      class_name, selector = *left_expr
      # return if [*rest].length > 1 # code is stubbing multiple methods
      remove(node.loc.selector)
      if selector == :any_instance
        remove(left_expr.loc.selector)
        remove(left_expr.loc.dot)
      end
      stubs = if selector == :any_instance
        remove(left_expr.loc.selector)
        remove(left_expr.loc.dot)
        Parser::AST::Node.new(
          :stubs, [class_name, rest, :allow_any], location: node.location
        )
      else
        Parser::AST::Node.new(
          :stubs, [left_expr, rest, :allow], location: node.location
        )
      end
      node.updated(nil, [process(stubs)])
    end

    def process_stub(node)
      replace(
        node.location.expression,
        convert_source_to_double(node.location.expression.source)
      )
    end

    def process_mock(node)
      replace(
        node.location.expression,
        convert_source_to_double(node.location.expression.source)
      )
    end

    def convert_source_to_double(source)
      source.gsub(/mock|stub/, "double")
    end

    def process_expects(node)
      left_expr, _variable_name, rest = *node
      remove(node.loc.selector)
      expects = Parser::AST::Node.new(
        :expects, [left_expr, rest], location: node.location
      )
      node.updated(nil, [process(expects)])
    end

    def process_returns(node)
      left_expr, _variable_name, *rest = *node
      multiline = false
      if rest.first.location.respond_to?(:begin) && rest.last.location.respond_to?(:end)
        multiline = (rest.first.location.begin&.line || 0) != (rest.last.location.end&.line || 0)
      end
      remove(node.loc.selector)
      remove(node.location.dot)
      if node.location.begin # return is in parens
        replace(node.location.begin, " { ") if node.location.begin
        replace(node.location.end, " }") if node.location.end
      else
        insert_before(rest.first.loc.expression, "{ ")
        insert_after(rest.last.loc.expression, " }")
      end
      if multiline
        # insert spaces between
        rest.each do |node|
          next if rest.first == node
          replace(node.loc.expression, " #{node.loc.expression.source}")
        end
      end

      argument_node = rest.flatten.first

      if argument_node.type == :hash && !argument_node.loc.begin
        wrap(argument_node.loc.expression, "{ ", " }")
      elsif rest.length > 1
        insert_before(rest.flatten.first.loc.expression, "[")
        insert_after(rest.flatten.last.loc.expression, "]")
      end
      node.updated(nil, [process(left_expr), rest.map { |n| process(n) }])
    end

    def process_with(node)
      left, _variable_name, rest = *node
      return false unless rest.nil? # with()
      remove(node.location.begin)
      remove(node.location.end)
      remove(node.location.selector)
      remove(node.location.dot)
      node.updated(nil, process(left))
      true
    end

    def process_never(node)
      left, _variable_name = *node
      left_expr, next_var, *rest = *left
      return false unless left_expr
      remove(node.loc.selector) && remove(node.loc.dot)
      remove(left.loc.selector)
      remove(left.loc.dot) if next_var != :expects
      remove(left.loc.begin) if left.loc.begin
      remove(left.loc.end) if left.loc.end
      new_node = Parser::AST::Node.new(
        next_var, [left_expr, *rest, :not], location: node.location
      )
      node.updated(nil, [process(new_node)])
      true
    end

    def process_raises(node)
      left, _variable_name, rest = *node
      remove(node.location.begin)
      remove(node.location.end)
      remove(node.location.selector)
      remove(node.location.dot)
      insert_before(node.loc.selector, " { raise ")
      insert_after(rest.loc.expression, " }")
      node.updated(nil, process(left))
    end

    def parse_receive_method(node)
      pairs = *node
      if pairs.length == 1 && [node].flatten.first.type == :hash
        hash, _rest = *node
        receives, returns = *hash
        receive_method = receives.loc.expression.source
        receive_method.prepend(":") if hash.loc.operator&.source == ":"
        [receive_method, returns]
      else
        [node.loc.expression.source, nil]
      end
    end
  end
end

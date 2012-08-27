require 'rubygems'
require 'interception'
require 'pry'

require File.expand_path('../pry-rescue/core_ext', __FILE__)
require File.expand_path('../pry-rescue/commands', __FILE__)

begin
  require 'pry-stack_explorer'
rescue LoadError
end

class PryRescue
  class << self

    # Start a Pry session in the context of the exception.
    # @param [Exception] exception The exception.
    # @param [Array<Binding>] bindings The call stack.
    def enter_exception_context(raised)

      raised = raised.map do |e, bs|
        [e, without_bindings_below_raise(bs)]
      end

      raised.pop if phantom_load_raise?(*raised.last)
      exception, bindings = raised.last

      if defined?(PryStackExplorer)
        pry :call_stack => bindings, :hooks => pry_hooks(exception, raised), :initial_frame => initial_frame(bindings)
      else
        Pry.start bindings.first, :hooks => pry_hooks(exception, raised)
      end
    end

    # Load a script wrapped in Pry::rescue{ }
    # @param [String] The name of the script
    def load(script)
      Pry::rescue{ Kernel.load script }
    end

    private

    # Did this raise happen within pry-rescue?
    #
    # This is designed to remove the extra raise that is caused by PryRescue.load.
    # TODO: we should figure out why it happens...
    # @param [Array<Binding>]
    def phantom_load_raise?(e, bindings)
      bindings.any? && bindings.first.eval("__FILE__") == __FILE__
    end

    # When using pry-stack-explorer we want to start the rescue session outside of gems
    # and the standard library, as that is most helpful for users.
    #
    # @param [Array<Bindings>]  All bindings
    # @return [Fixnum]  The offset of the first binding of user code
    def initial_frame(bindings)
      bindings.each_with_index do |binding, i|
        return i if user_path?(binding.eval("__FILE__"))
      end

      0
    end

    # Is this path likely to be code the user is working with right now?
    #
    # @param [String] the absolute path
    # @return [Boolean]
    def user_path?(file)
      !file.start_with?(RbConfig::CONFIG['libdir']) &&
      !Gem::Specification.any?{ |gem| file.start_with?(gem.full_gem_path) }
    end

    # Remove bindings that are part of Interception/Pry.rescue's internal
    # event handling that happens as part of the exception hooking process.
    #
    # @param [Array<Binding>] bindings The call stack.
    def without_bindings_below_raise(bindings)
      return bindings if bindings.size <= 1
      bindings.drop_while do |b|
        b.eval("__FILE__") == File.expand_path("../pry-rescue/core_ext.rb", __FILE__)
      end.drop_while do |b|
        b.eval("self") == Interception
      end
    end

    # Define the :before_session hook for the Pry instance.
    # This ensures that the `_ex_` and `_raised_` sticky locals are
    # properly set.
    def pry_hooks(ex, raised)
      hooks = Pry.config.hooks.dup
      hooks.add_hook(:before_session, :save_captured_exception) do |_, _, _pry_|
        _pry_.last_exception = ex
        _pry_.backtrace = ex.backtrace
        _pry_.sticky_locals.merge!({ :_raised_ => raised })
        _pry_.exception_handler.call(_pry_.output, ex, _pry_)
      end

      hooks
    end
  end
end

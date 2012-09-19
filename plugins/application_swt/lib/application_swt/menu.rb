module Redcar
  class ApplicationSWT
    class Menu

      def self.types
        @types = { :check => Swt::SWT::CHECK, :radio => Swt::SWT::RADIO }
      end

      def self.items
        @items ||= Hash.new {|h,k| h[k] = []}
      end

      def self.disable_items(key_string)
        items[key_string].each {|i| p i.text; i.enabled = false}
      end

      attr_reader :menu_bar

      def self.menu_types
        [Swt::SWT::BAR, Swt::SWT::POP_UP]
      end

      def initialize(window, menu_model, keymap, type, options={})
        s = Time.now
        unless Menu.menu_types.include?(type)
          raise "type should be in #{Menu.menu_types.inspect}"
        end
        @window = window
        @keymap = keymap
        @menu_bar = Swt::Widgets::Menu.new(window.shell, type)
        @menu_bar.set_visible(false)
        
        return unless menu_model
        @handlers = []
        @use_numbers = options[:numbers]
        @number = 1
        
        add_entries_to_menu(@menu_bar, nil, menu_model)
        #puts "ApplicationSWT::Menu initialize took #{Time.now - s}s"
      end

      def show
        @menu_bar.set_visible(true)
      end

      def close
        @handlers.each {|obj, h| obj.remove_listener(h) }
        @menu_bar.dispose
        @result
      end

      def move(x, y)
        @menu_bar.setLocation(x, y)
      end

      private

      def use_numbers?
        @use_numbers
      end

      class MenuListener
        attr_reader :items
        
        def initialize
          @items = []
        end
        
        def menu_shown(e)
          items.each do |item, entry|
            if entry.type == :check
              item.setSelection(entry.checked?)
            end
          end
        end
        
        def menu_hidden(e)
        end
      end

      def add_entries_to_menu(menu, menu_listener, menu_model)
        menu_model.each do |entry|
          if entry.is_a?(Redcar::Menu::LazyMenu)
            menu_header = Swt::Widgets::MenuItem.new(menu, Swt::SWT::CASCADE)
            menu_header.text = entry.text
            new_menu = Swt::Widgets::Menu.new(menu)
            menu_header.menu = new_menu
            menu_header.add_arm_listener do |e|
              new_menu.get_items.each {|i| i.dispose }
              add_entries_to_menu(new_menu, nil, entry)
            end
          elsif entry.is_a?(Redcar::Menu)
            menu_header = Swt::Widgets::MenuItem.new(menu, Swt::SWT::CASCADE)
            menu_header.text = entry.text
            new_menu = Swt::Widgets::Menu.new(menu)
            menu_header.menu = new_menu
            menu_header.enabled = (entry.length > 0)
            new_menu_listener = MenuListener.new
            add_entries_to_menu(new_menu, new_menu_listener, entry)
            new_menu.add_menu_listener(new_menu_listener)
            menu_header.add_arm_listener do |e|
              entry.entries.zip(new_menu.get_items) do |sub_entry, swt_item|
                if sub_entry.lazy_text?
                  swt_item.text = sub_entry.text
                end
              end
            end
          elsif entry.is_a?(Redcar::Menu::Item::Separator)
            item = Swt::Widgets::MenuItem.new(menu, Swt::SWT::SEPARATOR)
          elsif entry.is_a?(Redcar::Menu::Item)
            item = Swt::Widgets::MenuItem.new(menu, Menu.types[entry.type] || Swt::SWT::PUSH)
            if entry.command.is_a?(Proc)
              connect_proc_to_item(item, entry)
            else
              connect_command_to_item(item, entry)
            end
            if [:check, :radio].include? entry.type
              menu_listener.items << [item, entry] if menu_listener
              item.setSelection(entry.checked?)
            end
          else
            raise "unknown object of type #{entry.class} in menu"
          end
        end
      end

      class ProcSelectionListener
        def initialize(entry)
          @entry = entry
        end

        def widget_selected(e)
          Redcar.safely("menu item '#{@entry.text}'") do
            @entry.command.call
          end
        end

        alias :widget_default_selected :widget_selected
      end

      def connect_proc_to_item(item, entry)
        if use_numbers? and Redcar.platform == :osx
          item.text = entry.text + "\t" + @number.to_s
          @number += 1
        else
          item.text = entry.text
        end
        if entry.enabled?
          item.addSelectionListener(ProcSelectionListener.new(entry))
        else
          item.enabled = false
        end
      end

      class SelectionListener
        def initialize(entry)
          @entry = entry
        end

        def widget_selected(e)
          @entry.selected(e.stateMask != 0)
        end

        def widget_default_selected(e)
          @entry.selected(e.stateMask != 0)
        end
      end

      def connect_command_to_item(item, entry)
        if key_specifier = @keymap.command_to_key(entry.command)
          if key_string    = BindingTranslator.platform_key_string(key_specifier)
            item.text = entry.text + "\t" + key_string
            item.set_accelerator(BindingTranslator.key(key_string))
            Menu.items[key_string] << item
          else
            puts "you didn't specify a keybinding for this platform for #{entry.text}"
            item.text = entry.text
          end
        else
          item.text = entry.text
        end
        if entry.enabled?
          item.add_selection_listener(SelectionListener.new(entry))
          h = entry.command.add_listener(:active_changed) do |value|
            unless item.disposed
              item.enabled = value
            end
          end
          @handlers << [entry.command, h]
          if not entry.command.active?
            item.enabled = false
          end
        else
          item.enabled = false
        end
      end
    end
  end
end

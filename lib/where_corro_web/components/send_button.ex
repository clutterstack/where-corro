defmodule WhereCorroWeb.Components.SendButton do
  use Phoenix.Component

  attr :sending, :boolean, default: false
  attr :last_sent, :map, default: nil

  def send_button(assigns) do
    ~H"""
    <div class="inline-flex items-center space-x-4">
      <button
        phx-click="send_message"
        disabled={@sending}
        class={[
          "px-6 py-3 rounded-lg font-medium transition-all duration-200 transform",
          if @sending do
            "bg-gray-400 text-gray-600 cursor-not-allowed scale-95"
          else
            "bg-blue-600 text-white hover:bg-blue-700 hover:scale-105 active:scale-95"
          end
        ]}
      >
        <%= if @sending do %>
          <span class="flex items-center">
            <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Sending...
          </span>
        <% else %>
          Send Timestamp Message
        <% end %>
      </button>

      <%= if @last_sent do %>
        <div class="text-sm text-gray-600">
          <span class="font-medium">Last:</span>
          <span class="font-mono">#<%= @last_sent.sequence %></span>
        </div>
      <% end %>
    </div>
    """
  end
end

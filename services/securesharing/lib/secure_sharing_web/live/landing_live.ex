defmodule SecureSharingWeb.LandingLive do
  @moduledoc """
  Landing page for SecureSharing.
  """
  use SecureSharingWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {SecureSharingWeb.Layouts, :landing}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-blue-900 to-slate-900">
      <!-- Navigation -->
      <nav class="px-6 py-4">
        <div class="max-w-7xl mx-auto flex justify-between items-center">
          <div class="text-white font-bold text-xl">SecureSharing</div>
          <div class="space-x-4">
            <.link
              href={~p"/admin/login"}
              class="text-gray-300 hover:text-white px-4 py-2 text-sm font-medium transition"
            >
              Admin
            </.link>
          </div>
        </div>
      </nav>

      <!-- Hero Section -->
      <main class="max-w-7xl mx-auto px-6 pt-20 pb-32">
        <div class="text-center">
          <h1 class="text-5xl md:text-6xl font-bold text-white mb-6">
            Secure File Sharing
            <span class="block text-blue-400 mt-2">For The Quantum Era</span>
          </h1>
          <p class="text-xl text-gray-300 max-w-2xl mx-auto mb-10">
            Enterprise-grade file sharing protected by post-quantum cryptography.
            Your data stays safe, even against future quantum computers.
          </p>
          <div class="flex justify-center gap-4">
            <a
              href="#features"
              class="bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-medium transition"
            >
              Learn More
            </a>
            <a
              href="#api"
              class="border border-gray-500 hover:border-gray-400 text-gray-300 hover:text-white px-8 py-3 rounded-lg font-medium transition"
            >
              API Docs
            </a>
          </div>
        </div>

        <!-- Features Section -->
        <div id="features" class="mt-32 grid md:grid-cols-3 gap-8">
          <div class="bg-white/5 backdrop-blur rounded-xl p-8 border border-white/10">
            <div class="w-12 h-12 bg-blue-600 rounded-lg flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Post-Quantum Security</h3>
            <p class="text-gray-400">
              Protected by ML-KEM and KAZ-KEM algorithms. Future-proof encryption that withstands quantum attacks.
            </p>
          </div>

          <div class="bg-white/5 backdrop-blur rounded-xl p-8 border border-white/10">
            <div class="w-12 h-12 bg-blue-600 rounded-lg flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Zero-Knowledge Design</h3>
            <p class="text-gray-400">
              End-to-end encryption with client-side key management. We never see your data or keys.
            </p>
          </div>

          <div class="bg-white/5 backdrop-blur rounded-xl p-8 border border-white/10">
            <div class="w-12 h-12 bg-blue-600 rounded-lg flex items-center justify-center mb-4">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Multi-Tenant</h3>
            <p class="text-gray-400">
              Isolated workspaces for teams and organizations. Fine-grained access control and sharing permissions.
            </p>
          </div>
        </div>

        <!-- API Section -->
        <div id="api" class="mt-32 text-center">
          <h2 class="text-3xl font-bold text-white mb-4">RESTful API</h2>
          <p class="text-gray-400 max-w-xl mx-auto mb-8">
            Integrate secure file sharing into your applications with our comprehensive API.
          </p>
          <div class="bg-slate-800/50 rounded-xl p-6 max-w-2xl mx-auto text-left font-mono text-sm">
            <div class="text-gray-400 mb-2"># Upload a file</div>
            <div class="text-green-400">POST /api/files/upload-url</div>
            <div class="text-gray-400 mt-4 mb-2"># Share with another user</div>
            <div class="text-green-400">POST /api/shares/file</div>
            <div class="text-gray-400 mt-4 mb-2"># List received shares</div>
            <div class="text-green-400">GET /api/shares/received</div>
          </div>
        </div>
      </main>

      <!-- Footer -->
      <footer class="border-t border-white/10 py-8">
        <div class="max-w-7xl mx-auto px-6 text-center text-gray-500 text-sm">
          SecureSharing - Post-Quantum Secure File Sharing
        </div>
      </footer>
    </div>
    """
  end
end

import { BrowserRouter, Routes, Route, Link } from 'react-router-dom'

function DashboardPage() {
  return (
    <div>
      <h2 className="text-2xl font-semibold mb-4">Dashboard</h2>
      <p className="text-gray-600">Admin dashboard — coming soon.</p>
    </div>
  )
}

function App() {
  return (
    <BrowserRouter basename="/admin">
      <div className="min-h-screen bg-gray-50 text-gray-900">
        <header className="bg-white border-b border-gray-200 px-6 py-4">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <h1 className="text-xl font-bold">SSDID Drive Admin</h1>
            <nav className="flex gap-4 text-sm">
              <Link to="/" className="text-gray-600 hover:text-gray-900">
                Dashboard
              </Link>
            </nav>
          </div>
        </header>
        <main className="max-w-7xl mx-auto px-6 py-8">
          <Routes>
            <Route path="/" element={<DashboardPage />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  )
}

export default App

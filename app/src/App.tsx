import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './lib/auth'
import { isSupabaseConfigured } from './lib/supabase'
import LoginPage from './pages/LoginPage'
import AppLayout from './pages/AppLayout'
import DataEntryPage from './pages/DataEntryPage'

export default function App() {
  const { session, loading } = useAuth()

  if (isSupabaseConfigured && loading) {
    return <p className="p-6 text-sm text-slate-500">Loading…</p>
  }

  // When Supabase isn't configured, skip auth and render the app shell so the
  // dev experience isn't blocked. Pages display configuration banners instead.
  const authed = !isSupabaseConfigured || Boolean(session)

  return (
    <Routes>
      <Route path="/login" element={authed ? <Navigate to="/data-entry" replace /> : <LoginPage />} />
      <Route element={authed ? <AppLayout /> : <Navigate to="/login" replace />}>
        <Route index element={<Navigate to="/data-entry" replace />} />
        <Route path="/data-entry" element={<DataEntryPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

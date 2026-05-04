import { useState, type FormEvent } from 'react'
import { useAuth } from '../lib/auth'
import { isSupabaseConfigured } from '../lib/supabase'

export default function LoginPage() {
  const { signInWithMagicLink } = useAuth()
  const [email, setEmail] = useState('')
  const [status, setStatus] = useState<'idle' | 'sending' | 'sent' | 'error'>('idle')
  const [error, setError] = useState<string | null>(null)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setStatus('sending')
    setError(null)
    const { error } = await signInWithMagicLink(email)
    if (error) {
      setStatus('error')
      setError(error)
    } else {
      setStatus('sent')
    }
  }

  return (
    <div className="min-h-full flex items-center justify-center p-6">
      <div className="w-full max-w-sm bg-white border border-slate-200 rounded-lg shadow-sm p-6">
        <h1 className="text-xl font-semibold text-slate-900 mb-1">Staffing Matrix</h1>
        <p className="text-sm text-slate-600 mb-5">Sign in with a magic link sent to your work email.</p>

        {!isSupabaseConfigured && (
          <div className="mb-4 rounded border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            Supabase isn't configured. Copy <code>.env.example</code> to{' '}
            <code>.env.local</code> and set both keys.
          </div>
        )}

        <form onSubmit={onSubmit} className="space-y-3">
          <label className="block">
            <span className="block text-sm font-medium text-slate-700 mb-1">Email</span>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-md border-slate-300 focus:border-teal focus:ring-teal text-sm"
              placeholder="you@yourorg.com"
              disabled={!isSupabaseConfigured || status === 'sending' || status === 'sent'}
            />
          </label>
          <button
            type="submit"
            disabled={!isSupabaseConfigured || status === 'sending' || status === 'sent'}
            className="w-full rounded-md bg-teal text-white text-sm font-medium py-2 hover:bg-teal/90 disabled:opacity-50"
          >
            {status === 'sending' ? 'Sending…' : status === 'sent' ? 'Check your inbox' : 'Send magic link'}
          </button>
          {error && <p className="text-xs text-red-600">{error}</p>}
        </form>
      </div>
    </div>
  )
}

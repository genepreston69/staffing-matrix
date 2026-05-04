import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../lib/auth'

const navItems = [
  { to: '/data-entry', label: 'Data Entry' },
  { to: '/staffing',   label: 'Staffing',   disabled: true },
  { to: '/variance',   label: 'Variance',   disabled: true },
  { to: '/trends',     label: 'Trends',     disabled: true },
  { to: '/epob',       label: 'EPOB & Labor', disabled: true },
]

export default function AppLayout() {
  const { session, signOut } = useAuth()
  const email = session?.user?.email ?? 'Anonymous'

  return (
    <div className="min-h-full grid grid-cols-[220px_1fr]">
      <aside className="bg-teal text-white">
        <div className="px-5 py-4 border-b border-white/10">
          <div className="text-xs uppercase tracking-widest text-white/60">Staffing</div>
          <div className="text-base font-semibold">Highland</div>
        </div>
        <nav className="py-2">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                [
                  'block px-5 py-2 text-sm transition-colors border-l-4',
                  item.disabled
                    ? 'pointer-events-none text-white/30 border-transparent'
                    : isActive
                      ? 'text-white border-teal-accent bg-white/5'
                      : 'text-white/70 border-transparent hover:bg-white/5',
                ].join(' ')
              }
            >
              {item.label}
              {item.disabled && <span className="ml-2 text-[10px] uppercase opacity-60">soon</span>}
            </NavLink>
          ))}
        </nav>
        <div className="absolute bottom-0 w-[220px] px-5 py-3 border-t border-white/10 text-xs">
          <div className="truncate text-white/70">{email}</div>
          <button onClick={signOut} className="mt-1 text-white/60 hover:text-white">
            Sign out
          </button>
        </div>
      </aside>

      <main className="p-6 overflow-auto">
        <Outlet />
      </main>
    </div>
  )
}

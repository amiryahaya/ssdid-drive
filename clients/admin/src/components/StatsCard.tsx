import type { ReactNode } from 'react'

interface StatsCardProps {
  title: string
  value: string | number
  icon?: ReactNode
  accent?: 'blue' | 'green' | 'purple' | 'amber' | 'gray'
}

const accentColors = {
  blue: 'border-l-blue-500',
  green: 'border-l-green-500',
  purple: 'border-l-purple-500',
  amber: 'border-l-amber-500',
  gray: 'border-l-gray-300',
}

export default function StatsCard({ title, value, icon, accent = 'gray' }: StatsCardProps) {
  return (
    <div className={`bg-white rounded-xl shadow-sm border border-gray-100 border-l-4 ${accentColors[accent]} p-5`}>
      <div className="flex items-center gap-2 mb-1">
        {icon && <span className="text-gray-400">{icon}</span>}
        <h3 className="text-xs font-medium text-gray-500 uppercase tracking-wide">{title}</h3>
      </div>
      <p className="text-2xl font-semibold text-gray-900">{value}</p>
    </div>
  )
}

import { useState, useRef, useEffect } from 'react'

const WELCOME_MESSAGE = {
  role: 'assistant',
  content:
    "I'm Giskard. Ask me anything about the Premier League — results, tables, streaks, goals, and more. Data covers the 2015/16 through 2025/26 seasons.",
}

function PrologDetails({ query, result }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="prolog-details">
      <button
        className="prolog-toggle"
        onClick={() => setOpen(o => !o)}
        aria-expanded={open}
      >
        {open ? '▾' : '▸'} Prolog details
      </button>
      {open && (
        <div className="prolog-body">
          <p className="prolog-label">Query</p>
          <pre className="prolog-code">{query}</pre>
          <p className="prolog-label">Result</p>
          <pre className="prolog-code">{result}</pre>
        </div>
      )}
    </div>
  )
}

function Message({ msg }) {
  const isUser = msg.role === 'user'
  return (
    <div className={`message-row ${isUser ? 'user-row' : 'assistant-row'}`}>
      {!isUser && (
        <div className="avatar" aria-hidden="true">
          &gt;
        </div>
      )}
      <div className={`bubble ${isUser ? 'user-bubble' : 'assistant-bubble'} ${msg.error ? 'error-bubble' : ''}`}>
        <p className="bubble-text">{msg.content}</p>
        {!isUser && msg.prologQuery && (
          <PrologDetails query={msg.prologQuery} result={msg.prologResult} />
        )}
      </div>
    </div>
  )
}

function TypingIndicator() {
  return (
    <div className="message-row assistant-row">
      <div className="avatar" aria-hidden="true">
        ⚽
      </div>
      <div className="bubble assistant-bubble typing-bubble">
        <span className="dot" />
        <span className="dot" />
        <span className="dot" />
      </div>
    </div>
  )
}

export default function App() {
  const [messages, setMessages] = useState([WELCOME_MESSAGE])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const bottomRef = useRef(null)
  const textareaRef = useRef(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, loading])

  async function handleSend() {
    const question = input.trim()
    if (!question || loading) return

    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: question }])
    setLoading(true)

    try {
      const res = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question }),
      })

      if (!res.ok) throw new Error(`HTTP ${res.status}`)

      const data = await res.json()
      setMessages(prev => [
        ...prev,
        {
          role: 'assistant',
          content: data.answer,
          prologQuery: data.prolog_query,
          prologResult: JSON.stringify(data.prolog_result, null, 2),
        },
      ])
    } catch {
      setMessages(prev => [
        ...prev,
        {
          role: 'assistant',
          content: 'Something went wrong reaching the server. Please try again.',
          error: true,
        },
      ])
    } finally {
      setLoading(false)
    }
  }

  function handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  function handleInput(e) {
    setInput(e.target.value)
    const el = textareaRef.current
    if (el) {
      el.style.height = 'auto'
      el.style.height = `${Math.min(el.scrollHeight, 140)}px`
    }
  }

  return (
    <div className="app">
      <header className="header">
        <span className="header-badge">PL</span>
        <div className="header-titles">
          <h1 className="header-title">Giskard</h1>
          <p className="header-sub">Premier League Q&amp;A</p>
        </div>
      </header>

      <main className="chat" role="log" aria-live="polite">
        {messages.map((msg, i) => (
          <Message key={i} msg={msg} />
        ))}
        {loading && <TypingIndicator />}
        <div ref={bottomRef} />
      </main>

      <footer className="input-area">
        <textarea
          ref={textareaRef}
          className="input"
          value={input}
          onChange={handleInput}
          onKeyDown={handleKeyDown}
          placeholder="Ask about the Premier League…"
          rows={1}
          disabled={loading}
          aria-label="Question input"
        />
        <button
          className="send-btn"
          onClick={handleSend}
          disabled={!input.trim() || loading}
          aria-label="Send question"
        >
          Send
        </button>
      </footer>
    </div>
  )
}

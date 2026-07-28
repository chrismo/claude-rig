// A workflow whose only job is to make the orchestrator<->subagent channels visible.
//
// Mental model: the script is plain JS running in ONE process. Subagents are
// separate Claude contexts spawned by agent(). They share NOTHING with each
// other or with the script except:
//   (1) the prompt string you hand them        (script -> agent)
//   (2) their final text / StructuredOutput    (agent -> script)
//   (3) the filesystem, via their own tools    (agent <-> agent, out of band)
// Everything else you think of as "passing context" is you, the script author,
// interpolating (2) into (1).

export const meta = {
  name: 'agent-comms-demo',
  description: 'Demonstrate how a workflow script actually talks to its subagents',
  phases: [
    { title: 'Origin', detail: 'one agent returns schema-validated JSON' },
    { title: 'Relay', detail: 'pipeline: data reaches agents only via string interpolation' },
    { title: 'Isolation', detail: 'agent asked about prior output with nothing interpolated' },
    { title: 'Sidechannel', detail: 'one agent Writes a file, another Reads it' },
  ],
}

// ---------------------------------------------------------------------------
// CHANNEL 1: agent -> script, structured.
// Passing `schema` forces the subagent to call a StructuredOutput tool instead
// of replying in prose. agent() then returns the *validated JS object*. No
// parsing, no regex, no "please respond in JSON" begging. If the model returns
// a bad shape, the tool layer rejects it and the model retries.
// ---------------------------------------------------------------------------
const ORIGIN_SCHEMA = {
  type: 'object',
  properties: {
    codeword: { type: 'string', description: 'one uncommon English word' },
    number: { type: 'integer', description: 'between 1000 and 9999' },
  },
  required: ['codeword', 'number'],
  additionalProperties: false,
}

phase('Origin')
const origin = await agent(
  'Invent one uncommon English codeword and one integer between 1000 and 9999. Return them.',
  { schema: ORIGIN_SCHEMA, label: 'origin' },
)
// `origin` is a real object here. This log line is the proof.
log(`origin agent returned: codeword=${origin.codeword} number=${origin.number}`)

// ---------------------------------------------------------------------------
// CHANNEL 2: script -> agent, by interpolation. This is the ONLY way agent B
// learns anything agent A produced. Note the template literal below: that is
// literally the entire inter-agent bus.
//
// pipeline() runs each item through every stage independently, with no barrier
// between stages. Stage callbacks get (previousStageResult, originalItem, index)
// -- which is how `style` is still in scope in stage 2 without threading it
// through stage 1's return value.
// ---------------------------------------------------------------------------
phase('Relay')
const relayed = await pipeline(
  ['pirate', 'haiku'],
  (style) =>
    agent(
      `The codeword is "${origin.codeword}" and the number is ${origin.number}. ` +
        `Write ONE sentence in ${style} style using both. Return only the sentence.`,
      { label: `write:${style}`, phase: 'Relay' },
    ),
  (sentence, style) =>
    agent(`In 15 words or fewer, critique this ${style} line: "${sentence}"`, {
      label: `critique:${style}`,
      phase: 'Relay',
    }).then((critique) => ({ style, sentence, critique })),
)

// ---------------------------------------------------------------------------
// THE CONTROL EXPERIMENT: same workflow, same run, but nothing interpolated.
// If subagents shared memory, this one could answer. It cannot.
// ---------------------------------------------------------------------------
phase('Isolation')
const blind = await agent(
  'Another agent in this same workflow run just chose a secret codeword and a ' +
    'number. State what they chose. Do not guess or invent one. If you have no ' +
    'channel through which to know, reply with exactly: NO_CHANNEL',
  { label: 'blind', phase: 'Isolation' },
)

// ---------------------------------------------------------------------------
// CHANNEL 3: the filesystem. The SCRIPT has no fs access (no require, no node
// APIs) -- but subagents are full Claude instances with Write/Read/Bash. So
// agents can hand each other payloads too big to interpolate, and the script
// only passes the path. This is how you move a 200KB report between stages
// without dragging it through the orchestrator's context.
// ---------------------------------------------------------------------------
// GOTCHA, hit for real on the first run of this very script: `args` arrives
// VERBATIM. Pass it as a JSON-encoded string and you get a string, not an
// object -- so `args.scratch` was `undefined` and the writer agent dutifully
// created `undefined/comms-demo-note.txt`. Defend, or pass a real object.
phase('Sidechannel')
const scratch = typeof args === 'string' ? JSON.parse(args).scratch : args.scratch
const notePath = `${scratch}/comms-demo-note.txt`
await agent(
  `Use the Write tool to create ${notePath} containing exactly: ${origin.codeword}-${origin.number}\nThen return only the word DONE.`,
  { label: 'writer', phase: 'Sidechannel' },
)
const readBack = await agent(
  `Use the Read tool on ${notePath} and return its exact contents and nothing else. ` +
    `You have not been told what it contains.`,
  { label: 'reader', phase: 'Sidechannel' },
)

// The return value of the script is what the Workflow tool hands back to me.
return {
  origin,
  relayed,
  blind_agent_said: blind,
  reader_agent_recovered: readBack,
}

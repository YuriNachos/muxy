# Tips

Muxy's built-in sidebar tips are stored in `Muxy/Resources/tips.json`. The file is bundled with the app, decoded once
per process, and never fetched from a remote service.

Each entry has exactly one field:

```json
{
  "description": "A concise, actionable tip."
}
```

Descriptions must contain non-whitespace text. They may contain inline Markdown links when a tip needs to reference
Muxy documentation. Do not add names, identifiers, categories, links, display rules, or other fields. Keep the JSON
order intentional because the previous and next buttons follow it.

Muxy chooses a random starting entry once per app launch. It does not rotate tips automatically. Missing, malformed,
empty, or invalid catalogs are logged and leave the tip interface hidden.

Closing a tip asks for confirmation before hiding the interface. Tips can be restored from
**Settings → Interface → Sidebar → Show Tips**.

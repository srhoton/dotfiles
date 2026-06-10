Research the following topic using web tools and return a concise, actionable summary: $ARGUMENTS

Steps:
1. Run WebSearch on the query.
2. From the top 3-5 results, pick the most authoritative source. Priority: official docs > vendor blog > Stack Overflow > community blog.
3. WebFetch the chosen source. If it points to additional pages with the actual content (e.g., a doc index linking out to specific guides), follow one more level.
4. Produce a summary covering:
   - **Short answer** to my question (1-2 sentences)
   - **Relevant snippets** (code, config, commands)
   - **Source URL**
   - **Common pitfalls** or gotchas noted in the source
5. If the answer isn't clear from the web sources, say so explicitly — do not fabricate.

Source preferences:
- AWS questions → `docs.aws.amazon.com` first
- Terraform → `registry.terraform.io` or `developer.hashicorp.com`
- npm packages → `npmjs.com` + the package's GitHub README
- Java/JVM → `docs.oracle.com` or the library's official docs
- TypeScript/JS → `developer.mozilla.org` for web APIs, `typescriptlang.org` for language features

Constraints:
- Response under ~300 lines.
- Mark community sources clearly when used.
- Don't paste the entire fetched page back; extract only what's needed.

# X (x.com)
Carried over from v1 notes, not re-verified on v2. <t> = tab id.

## Search pacing
- Several tabs searching in parallel got "Something went wrong" (ScriptLoadFailure) after about 10 loads each.
- One tab with about 25 s between loads ran 18 searches cleanly. Search one at a time.

## Read tweets
- `umb run <t> -` over `article[data-testid=tweet]`: url from `a[href*="/status/"]`, time from `time[datetime]`, text from `[data-testid=tweetText]`, counts from the `aria-label` of `[role=group]`. Return one joined string, not an array.

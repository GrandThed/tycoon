Found 2026-09-22 during the M9 wave 2a Studio playtest (tiles pointing the wrong way, the ramp running
back over the ring, cars driving tail-first): **Roblox's glTF import turns every harvested model 180°
about Y** (+Z-forward → −Z-forward). Since M7 the harvest offsets carried that turn (blueprint centre
+7.0 → harvested −6.965) and `gen_templates.py` compensated only path meshes, so every building in
every era faced away from its pad and every prop was backwards; nobody noticed because most kit
buildings are near-symmetric. Fixed in commit b17718e: one `harvested_cframe` path for buildings,
props and paths (paths byte-identical). The client must never compensate again (a temporary
`PropFactory.TEMPLATE_TURN` was added and removed the same day).

**Why:** a fresh session seeing an oriented prop backwards would patch the client or the blueprint
instead of trusting the template turn, and re-open the double-compensation.

**How to apply:** when a template's facing looks wrong, read the .rbxmx CFrame (R00 = R22 = −1 is
correct) before touching code; verify orientation offline with `py tools/testfit/plotrender.py <Era>`,
the plot-level render Ben now uses as the Studio reference. Every tile/prop orientation contract is
stated in the blueprint frame (front −Z). See [[metropolis-streets-2026-09-22]] and
[[assets-direction-2026-09-15]].

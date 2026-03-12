# SSDID Drive — Role Matrix

## System Roles

| Role | Scope | Description |
|------|-------|-------------|
| SuperAdmin | Platform | Full platform administration |

## Tenant Roles

| Role | Scope | Description |
|------|-------|-------------|
| Owner | Tenant | Full tenant control |
| Admin | Tenant | Member management (limited) |
| Member | Tenant | Standard access |

## Permission Matrix

| Action | SuperAdmin | Owner | Admin | Member |
|---|---|---|---|---|
| **Platform** | | | | |
| Create tenant | Yes | - | - | - |
| Edit/disable tenant | Yes | - | - | - |
| View all users | Yes | - | - | - |
| Suspend/activate user | Yes | - | - | - |
| Assign SuperAdmin role | Yes | - | - | - |
| View audit log | Yes | - | - | - |
| **Tenant Invitations** | | | | |
| Invite Owner | Yes | - | - | - |
| Invite Admin | Yes | Yes | - | - |
| Invite Member | - | Yes | Yes | - |
| Revoke own invitation | Yes | Yes | Yes | - |
| **Tenant Members** | | | | |
| View members | Yes | Yes | Yes | Yes |
| Change role to Owner | - | Yes | - | - |
| Change role to Admin | - | Yes | - | - |
| Change role to Member | - | Yes | Yes* | - |
| Remove member | - | Yes | Yes* | - |

*Admin can only manage Members, not other Admins or Owners. SuperAdmin does not invite Members — that's the responsibility of tenant Owners/Admins via the desktop client.

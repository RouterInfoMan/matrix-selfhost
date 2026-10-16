# Installation guide

This guide takes you from an empty machine to a working Matrix server with
your first account. Follow the steps in order. One step sends you to a short
page for your chosen setup, and that page sends you back here.

**Contents**
1. [Choose how people will reach your server](#1-choose-how-people-will-reach-your-server)
2. [Prepare the machine](#2-prepare-the-machine)
3. [Get the code](#3-get-the-code)
4. [Choose your names](#4-choose-your-names)
5. [Set up your mode](#5-set-up-your-mode)
6. [Start the server](#6-start-the-server)
7. [Create your account and sign in](#7-create-your-account-and-sign-in)
8. [Invite people](#8-invite-people)
9. [Next steps](#9-next-steps)

---

## 1. Choose how people will reach your server

Your chat apps need a way to reach the server. Pick one of four **modes**:

| Mode | Choose it if… | You need |
|---|---|---|
| **`public`** | The machine has a public IP address: any VPS, or a home server where you can forward ports. | A domain at any DNS provider. Ports 80 and 443 open. |
| **`cloudflare`** | The machine **can't** accept incoming connections (behind CGNAT or a strict firewall), or you don't want to open ports. | A domain using Cloudflare's (free) DNS. |
| **`local`** | You want to try it on your own computer, or use it only on your home network. | Nothing for a trial. For your home network, a way to add local DNS names. |
| **`proxy`** | The machine already runs a web server or reverse proxy (nginx, Traefik, …) on ports 80/443. | That proxy handles certificates and routing. |

If you're unsure:
- To just try it, choose **`local`**.
- If it's a VPS, choose **`public`**.
- If it's a home machine and you can't (or won't) forward ports, choose
  **`cloudflare`**.

You can switch modes later without losing data.

## 2. Prepare the machine

**Operating system:** any modern 64-bit Linux, such as Debian, Ubuntu,
Fedora, or Raspberry Pi OS. On Windows, use WSL2. On macOS, Docker Desktop
works for a local trial.

**Resources:** 1 GB of RAM is the minimum and 2 GB is comfortable for a small
group. Uploaded files are stored on disk, so leave a few GB free.

**Docker:** install Docker Engine and the Compose plugin:

```sh
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and back in, so the group change takes effect. Then check that it
works:

```sh
docker run --rm hello-world
docker compose version
```

**Remote servers:** you can run everything directly on the server, or keep
the repository on your own computer and deploy over SSH (step 6). For the
latter, make sure `ssh user@your-server` works without problems.

## 3. Get the code

On the server, or on your own computer if you'll deploy over SSH:

```sh
git clone <repository-url> matrix
cd matrix
cp .env.example .env
```

`.env` holds all your settings. It's excluded from git, so it never ends up
in the repository.

## 4. Choose your names

Open `.env` in an editor and set the **mode** and **three names**:

```ini
MODE=public                       # from step 1
SERVER_NAME=example.com           # appears in user IDs: @alice:example.com
MATRIX_HOST=matrix.example.com    # where the server itself is reached
ELEMENT_HOST=chat.example.com     # where the web chat app is reached
```

> ⚠️ **`SERVER_NAME` is permanent.** It becomes part of every account
> (`@alice:example.com`) and can't be changed later without deleting
> everything. Pick it carefully.

Common choices:

| You want IDs like | Set | Notes |
|---|---|---|
| `@alice:example.com` | `SERVER_NAME=example.com` | The nicest IDs. Requests to `example.com/.well-known/matrix/*` must reach this server. That's automatic in `public` and `local` modes, and one extra route in `cloudflare` mode. |
| `@alice:matrix.example.com` | `SERVER_NAME=matrix.example.com` (same as `MATRIX_HOST`) | Use this if `example.com` already hosts a website you can't touch. |
| `@alice:matrix.localhost` | all three set to `*.localhost` names | Local trial only: `matrix.localhost` and `chat.localhost`. |

The other settings (invite-only sign-up, federation off, upload limit) have
sensible defaults. See [configuration.md](configuration.md) if you want to
change them.

## 5. Set up your mode

Each mode needs a few specific steps: DNS records, a tunnel, open ports, or
proxy rules. Follow the page for your mode, then come back here for step 6.

- [`public`: public server, any DNS provider](modes/public.md)
- [`cloudflare`: Cloudflare Tunnel](modes/cloudflare.md)
- [`local`: this computer or your home network](modes/local.md)
- [`proxy`: behind your existing reverse proxy](modes/proxy.md)

## 6. Start the server

**If you're on the server itself:**

```sh
./matrix.sh up
```

**If you're deploying from your own computer:**

```sh
./deploy.sh user@your-server
```

This copies the repository to `~/matrix` on the server and runs
`./matrix.sh up` there. Your data stays on the server. Later runs of
`deploy.sh` only update the configuration.

The first start takes a few minutes while Docker downloads the images. It
also creates `data/`, which holds your database, uploaded files, the server's
identity key, and generated passwords. Treat `data/` as precious and private.

Then check that everything is up. On the server, run:

```sh
./matrix.sh status
```

Every line should say `OK`. If one doesn't, see
[troubleshooting.md](troubleshooting.md).

## 7. Create your account and sign in

Sign-up is invite-only, so create the first (admin) account from the
command line, on the server:

```sh
./matrix.sh adduser yourname --admin
```

It asks for a password. Then:

- **In a browser:** open your `ELEMENT_HOST` (e.g. `https://chat.example.com`)
  and click **Sign in**.
- **On phone or desktop:** install a Matrix app, such as
  [Element X](https://element.io/download), [FluffyChat](https://fluffychat.im),
  or [others](https://matrix.org/ecosystem/clients/). When it asks for a
  server, choose a custom or other server and enter your `SERVER_NAME`.

The first time you sign in, the app offers to set up a **recovery key**.
**Save it somewhere safe.** Messages are end-to-end encrypted, and without
this key a new device can't read your message history. Not even the server
administrator can recover it.

## 8. Invite people

Create an invite token on the server:

```sh
./matrix.sh invite          # one use, valid for 7 days
./matrix.sh invite 10 30    # ten uses, valid for 30 days
```

It prints a message to send to the person. They open your chat address,
click **Create account**, choose a username and password, and paste the token
when asked.

Alternatively, create accounts for people yourself with
`./matrix.sh adduser theirname`.

## 9. Next steps

- **Set up backups.** Run `./matrix.sh backup`, copy the result off the
  server, and consider a nightly cron job. See
  [operations.md](operations.md#backups).
- **Keep it updated.** Run `./matrix.sh update` every few weeks.
- **Want to chat with people on other Matrix servers** (matrix.org and
  others)? Set `ENABLE_FEDERATION=true`, as described in
  [configuration.md](configuration.md#federation).
- **Read [security.md](security.md)** to understand what's private and from
  whom.

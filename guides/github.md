
### Настройка SSH ключа для GitHub

#### 1. Добавьте SSH ключ в ssh-agent

**Запустите ssh-agent**

```bash
eval "$(ssh-agent -s)"
```

**Добавьте SSH ключ в ssh-agent**

```
ssh-add ~/.ssh/id_ed25519
```

#### 2. Скопируйте публичный ключ

```bash
cat ~/.ssh/id_ed25519.pub
```

Скопируйте весь вывод (начинается с `ssh-ed25519`).

#### 3. Добавьте ключ на GitHub

1. Откройте [GitHub.com](https://github.com) и войдите в аккаунт
2. Нажмите на аватар → **Settings**
3. В левом меню выберите **SSH and GPG keys**
4. Нажмите **New SSH key**
5. **Title**: Введите описание (например, "Мой рабочий ноутбук")
6. **Key type**: Authentication Key
7. **Key**: Вставьте скопированный публичный ключ
8. Нажмите **Add SSH key**

#### 4. Проверьте подключение

```bash
ssh -T git@github.com
```

Должно появиться сообщение:

```bash
Hi username! You've successfully authenticated, but GitHub does not provide shell access.
```

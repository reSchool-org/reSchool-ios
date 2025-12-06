import requests
import hashlib
import json
import time
import random
import string
import os
import re
from datetime import datetime, timedelta
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.prompt import Prompt, Confirm
from rich.text import Text
from rich import box
import sys

class ESchoolAPI:
    BASE_URL = "https://app.eschool.center/ec-server"
    SESSION_FILE = "eschool_session.json"

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'ru-RU,ru;q=0.9',
            'Origin': 'https://app.eschool.center',
            'Referer': 'https://app.eschool.center/',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
            'Sec-Ch-Ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"macOS"',
            'Priority': 'u=1, i'
        })
        self.username = None
        self.user_id = None
        self.prs_id = None
        self.session_id = None
        self.profile_data = None

    def _generate_random_string(self, length):
        return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

    def _get_headers(self):
        headers = {}
        if self.session_id:
            headers['Cookie'] = f'JSESSIONID={self.session_id}'
        return headers

    def save_session_data(self, username, password_hash, device_payload):
        data = {
            "username": username,
            "password_hash": password_hash,
            "device_payload": device_payload
        }
        try:
            with open(self.SESSION_FILE, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=4)
        except Exception as e:
            pass 

    def load_session_data(self):
        if not os.path.exists(self.SESSION_FILE):
            return None
        try:
            with open(self.SESSION_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            return None

    def auto_login(self):
        data = self.load_session_data()
        if not data:
            return False
        
        username = data.get("username")
        password_hash = data.get("password_hash")
        device_payload = data.get("device_payload")
        
        if not all([username, password_hash, device_payload]):
            return False

        return self._perform_login_request(username, password_hash, device_payload)

    def login(self, username, password):
        password_hash = hashlib.sha256(password.encode('utf-8')).hexdigest()
        
        device_id = self._generate_random_string(32)
        push_token = self._generate_random_string(64)

        device_payload = {
            "cliType": "web",
            "cliVer": "v.2515",
            "pushToken": push_token, 
            "deviceId": device_id,
            "deviceName": "Chrome",
            "deviceModel": 120,
            "cliOs": "MacIntel",
            "cliOsVer": None
        }

        success = self._perform_login_request(username, password_hash, device_payload)
        if success:
            self.save_session_data(username, password_hash, device_payload)
        return success

    def _perform_login_request(self, username, password_hash, device_payload):
        self.username = username
        data = {
            "username": username,
            "password": password_hash,
            "device": json.dumps(device_payload) if isinstance(device_payload, dict) else device_payload
        }

        try:
            response = self.session.post(f"{self.BASE_URL}/login", data=data)
            
            if response.status_code != 200:
                 error_text = response.text
                 if "503" in error_text:
                     raise Exception("Сервер временно недоступен (503). Попробуйте позже.")
                 raise Exception(f"HTTP Error {response.status_code}")

            if 'Set-Cookie' in response.headers:
                cookies = response.headers['Set-Cookie']
                for cookie in cookies.split(';'):
                    if 'JSESSIONID=' in cookie:
                        self.session_id = cookie.split('JSESSIONID=')[1].split(';')[0]
                        self.session.cookies.set('JSESSIONID', self.session_id, domain='app.eschool.center')
                        return True
            
            if self.session.cookies.get('JSESSIONID'):
                self.session_id = self.session.cookies.get('JSESSIONID')
                return True

            if response.text in ["1", "3", "4"]:
                return False
            
            if len(response.text) > 5: 
                 return True

            return False

        except Exception as e:
            if "HTTP Error" in str(e) or "503" in str(e):
                raise e
            return False

    def get_state(self):
        response = self.session.get(f"{self.BASE_URL}/state", headers=self._get_headers())
        if response.status_code != 200:
            raise Exception(f"Ошибка получения профиля: {response.status_code}")
        data = response.json()
        self.user_id = data.get('userId')
        self.prs_id = data.get('user', {}).get('prsId')
        self.profile_data = data.get('profile')
        return data

    def get_threads(self, new_only=False, row=0, rows_count=20):
        url = f"{self.BASE_URL}/chat/threads"
        params = {
            "newOnly": str(new_only).lower(),
            "row": row,
            "rowsCount": rows_count
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_messages(self, thread_id, row_start=0, rows_count=25):
        url = f"{self.BASE_URL}/chat/messages"
        params = {
            "getNew": "false",
            "isSearch": "false",
            "rowStart": row_start,
            "rowsCount": rows_count,
            "threadId": thread_id
        }
        payload = {"msgNums": None, "searchText": None}
        response = self.session.put(url, params=params, json=payload, headers=self._get_headers())
        return response.json()

    def send_message(self, thread_id, msg_text):
        url = f"{self.BASE_URL}/chat/sendNew"
        msg_uid = str(int(time.time() * 1000))
        files = {
            'threadId': (None, str(thread_id)),
            'msgText': (None, str(msg_text)),
            'msgUID': (None, msg_uid)
        }
        response = self.session.post(url, files=files, headers=self._get_headers())
        return response.json()
    
    def get_groups_tree(self):
        url = f"{self.BASE_URL}/groups/tree"
        params = {
            "bAllTypes": "false",
            "bApplicants": "true",
            "bEmployees": "true",
            "bGroups": "true"
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def save_thread(self, interlocutor_id):
        url = f"{self.BASE_URL}/chat/saveThread"
        data = {
            "threadId": None,
            "senderId": None,
            "imageId": None,
            "subject": None,
            "isAllowReplay": 2,
            "isGroup": False,
            "interlocutor": interlocutor_id
        }
        response = self.session.put(url, json=data, headers=self._get_headers())
        return response.json()

    def get_class_by_user(self):
        if not self.user_id:
            self.get_state()
        url = f"{self.BASE_URL}/usr/getClassByUser"
        params = {"userId": self.user_id}
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_periods(self, group_id):
        url = f"{self.BASE_URL}/dict/periods/0"
        params = {"groupId": group_id}
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_diary_units(self, period_id):
        if not self.user_id:
            self.get_state()
        url = f"{self.BASE_URL}/student/getDiaryUnits/"
        params = {"userId": self.user_id, "eiId": period_id}
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()
    
    def get_diary_period(self, period_id):
        if not self.user_id:
            self.get_state()
        url = f"{self.BASE_URL}/student/getDiaryPeriod_/" 
        params = {"userId": self.user_id, "eiId": period_id}
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_prs_diary(self, d1, d2):
        if not self.prs_id:
            self.get_state()
        
        url = f"{self.BASE_URL}/student/getPrsDiary"
        params = {
            "prsId": self.prs_id,
            "d1": d1,
            "d2": d2
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_pupil_units(self, prs_id, year_id):
        url = f"{self.BASE_URL}/student/getPupilUnits"
        params = {
            "prsId": prs_id,
            "yearId": year_id
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_user_list_search(self, year_id):
        url = f"{self.BASE_URL}/usr/getUserListSearch"
        params = {
            "yearId": year_id
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_lpart_list_pupil(self, beg_date, end_date, is_odod, prs_id, year_id):
        url = f"{self.BASE_URL}/student/getLPartListPupil"
        params = {
            "begDate": beg_date,
            "endDate": end_date,
            "isOdod": is_odod,
            "prsId": prs_id,
            "yearId": year_id
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

    def get_profile_new(self, prs_id):
        url = f"{self.BASE_URL}/profile/getProfile_new"
        params = {
            "prsId": prs_id
        }
        response = self.session.get(url, params=params, headers=self._get_headers())
        return response.json()

console = Console()
api = ESchoolAPI()

def clear_screen():
    console.clear()

def print_header(title="eSchool CLI"):
    grid = Table.grid(expand=True)
    grid.add_column(justify="center", ratio=1)
    grid.add_row(Panel(Text(title, justify="center", style="bold cyan"), style="cyan", box=box.HEAVY))
    console.print(grid)

def clean_html(raw_html):
    if not raw_html:
        return ""
    cleanr = re.compile('<.*?>')
    text = raw_html.replace('<br>', '\n').replace('</p>', '\n').replace('<p>', '')
    text = re.sub(cleanr, '', text)
    return text.strip()

def login_screen():
    if os.path.exists(ESchoolAPI.SESSION_FILE):
        with console.status("[bold blue]Вход по сохраненным данным...[/bold blue]", spinner="dots"):
            try:
                if api.auto_login():
                    api.get_state()
                    console.print("[bold green]Автоматический вход выполнен![/bold green]")
                    time.sleep(1)
                    return True
                else:
                    console.print("[yellow]Сохраненная сессия устарела.[/yellow]")
            except Exception as e:
                 console.print(f"[red]Ошибка авто-входа: {e}[/red]")
            time.sleep(1)

    clear_screen()
    print_header("Вход в систему")
    console.print("[yellow]Введите данные для входа в eSchool[/yellow]\n")
    username = Prompt.ask("[bold green]Логин[/bold green]")
    password = Prompt.ask("[bold green]Пароль[/bold green]", password=True)

    with console.status("[bold green]Авторизация...[/bold green]", spinner="dots"):
        try:
            success = api.login(username, password)
            if success:
                api.get_state() 
                console.print("[bold green]Успешный вход![/bold green]")
                time.sleep(1)
                return True
            else:
                console.print("[bold red]Не удалось войти.[/bold red]")
                time.sleep(2)
                return False
        except Exception as e:
            console.print(f"[bold red]Ошибка: {e}[/bold red]")
            time.sleep(3)
            return False

def show_profile():
    clear_screen()
    print_header("Профиль")
    try:
        state = api.get_state()
        profile = state.get('profile', {})
        user = state.get('user', {})
        table = Table(show_header=False, box=box.ROUNDED)
        table.add_column("Key", style="bold cyan")
        table.add_column("Value", style="white")
        table.add_row("ФИО", f"{profile.get('lastName')} {profile.get('firstName')} {profile.get('middleName')}")
        table.add_row("ID пользователя", str(profile.get('id', 'N/A')))
        table.add_row("Логин", user.get('username', 'N/A'))
        table.add_row("Телефон", profile.get('phoneMob', 'N/A'))
        table.add_row("Email", profile.get('email', 'N/A'))
        console.print(table)
    except Exception as e:
        console.print(f"[red]Ошибка загрузки профиля: {e}[/red]")
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_chats():
    while True:
        clear_screen()
        print_header("Сообщения")
        with console.status("Загрузка чатов...", spinner="dots"):
            threads = api.get_threads()
        
        table = Table(title="Ваши диалоги", box=box.SIMPLE_HEAD, show_lines=True)
        table.add_column("#", justify="right", style="cyan", no_wrap=True)
        table.add_column("Тема/Собеседник", style="magenta")
        table.add_column("Последнее сообщение", style="white")
        table.add_column("Дата", justify="right", style="green")
        
        thread_map = {}
        for idx, thread in enumerate(threads, 1):
            thread_map[idx] = thread['threadId']
            subject = thread.get('subject') or thread.get('senderFio') or "Без темы"
            preview = thread.get('msgPreview', '')[:50] + "..." if len(thread.get('msgPreview', '')) > 50 else thread.get('msgPreview', '')
            date_str = datetime.fromtimestamp(thread['sendDate'] / 1000).strftime('%d.%m %H:%M')
            table.add_row(str(idx), subject, preview, date_str)
            
        console.print(table)
        console.print("\n[dim]Введите номер чата, 'u' обновить, '0' выход[/dim]")
        choice = Prompt.ask("Выбор")
        
        if choice == '0': break
        elif choice.lower() == 'u': continue
        elif choice.isdigit() and int(choice) in thread_map:
            view_thread(thread_map[int(choice)])

def view_thread(thread_id):
    while True:
        clear_screen()
        with console.status("Загрузка сообщений...", spinner="dots"):
            messages = api.get_messages(thread_id)
            messages.reverse() 
        print_header("Чат")
        for msg in messages:
            sender = msg.get('senderFio', 'Неизвестный')
            text = msg.get('msg', '')
            date = datetime.fromtimestamp(msg['createDate'] / 1000).strftime('%H:%M')
            is_me = False
            if api.profile_data:
                 my_fio = f"{api.profile_data.get('lastName')} {api.profile_data.get('firstName')} {api.profile_data.get('middleName')}"
                 is_me = sender == my_fio
            color = "green" if is_me else "yellow"
            align = "right" if is_me else "left"
            msg_panel = Panel(f"{text}\n[dim]{date}[/dim]", title=f"[bold {color}]{sender}[/bold {color}]", title_align=align, border_style=color, width=60, expand=False)
            console.print(msg_panel, justify="right" if is_me else "left")
                
        console.print("\n[dim]'r' - ответить, 'u' - обновить, '0' - назад[/dim]")
        choice = Prompt.ask("Действие")
        if choice == '0': break
        elif choice.lower() == 'u': continue
        elif choice.lower() == 'r':
            text = Prompt.ask("[bold green]Ваше сообщение[/bold green]")
            if text:
                api.send_message(thread_id, text)
                console.print("[green]Отправлено![/green]")
                time.sleep(0.5)

def build_period_tree(periods_list):
    children = {}
    roots = []
    
    periods_list.sort(key=lambda x: x.get('date1', 0))

    for p in periods_list:
        pid = p.get('parentId')
        if not pid:
            roots.append(p)
        else:
            if pid not in children:
                children[pid] = []
            children[pid].append(p)

    result = []
    def recurse(nodes, depth):
        for node in nodes:
            node['depth'] = depth
            result.append(node)
            node_id = node.get('id')
            if node_id in children:
                recurse(children[node_id], depth + 1)
    
    recurse(roots, 0)
    return result

def select_period_option():
    with console.status("Загрузка данных для всех классов...", spinner="dots"):
        try:
            groups = api.get_class_by_user()
            if not groups:
                console.print("[red]Классы не найдены[/red]")
                return None
            
            groups.sort(key=lambda x: x.get('begDate', 0))

            all_options = []

            for group in groups:
                group_id = group['groupId']
                group_name = group.get('groupName', f"Group {group_id}")
                
                periods_data = api.get_periods(group_id)
                
                root_period = periods_data.copy()
                if 'items' in root_period:
                    del root_period['items']
                
                root_period['depth'] = 0
                root_period['is_root'] = True
                root_period['group_name'] = group_name
                
                all_options.append({'period': root_period, 'group_id': group_id})

                flat_sub_periods = build_period_tree(periods_data.get('items', []))
                
                for p in flat_sub_periods:
                    p['depth'] = p.get('depth', 0) + 1
                    all_options.append({'period': p, 'group_id': group_id})

            return all_options

        except Exception as e:
            console.print(f"[red]Ошибка: {e}[/red]")
            return None

def show_diary():
    clear_screen()
    print_header("Дневник")
    
    options = select_period_option()
    if not options:
        Prompt.ask("Enter для возврата")
        return

    table = Table(title="Выберите период (Класс / Год)", box=box.SIMPLE)
    table.add_column("#", style="cyan")
    table.add_column("Название", style="white")
    table.add_column("Даты", style="green")
    
    period_map = {}
    current_option_idx = None
    now = time.time() * 1000
    
    for idx, opt in enumerate(options, 1):
        period_map[idx] = opt
        p = opt['period']
        name = p['name']
        
        prefix = "  " * p.get('depth', 0)
        
        if p.get('is_root'):
            display_name = f"[bold blue]{p.get('group_name')}[/bold blue]: {name}"
        else:
            display_name = prefix + name

        dates = f"{p['date1Str']} - {p['date2Str']}"
        style = "white"
        
        if p['date1'] <= now <= p['date2']:
            if not p.get('is_root'):
                 style = "bold yellow"
                 display_name = f"{prefix}{name} (Текущий)"
                 current_option_idx = str(idx)
        
        table.add_row(str(idx), display_name, dates)
        
    console.print(table)
    
    default_val = current_option_idx if current_option_idx else "1"
    choice = Prompt.ask("Выберите номер", default=default_val)
    
    if not choice.isdigit() or int(choice) not in period_map: return

    selected_opt = period_map[int(choice)]
    selected_period = selected_opt['period']
    selected_group_id = selected_opt['group_id']
    
    with console.status("Загрузка оценок...", spinner="dots"):
        diary_units = api.get_diary_units(selected_period['id'])
        units_list = diary_units.get('result', [])
        
        diary_details = api.get_diary_period(selected_period['id'])
        lessons = diary_details.get('result', [])

    marks_map = {} 
    for lesson in lessons:
        unit_id = lesson.get('unitId')
        parts = lesson.get('part', [])
        for part in parts:
            marks = part.get('mark', [])
            for mark in marks:
                val = mark.get('markValue')
                if val:
                    if unit_id not in marks_map:
                        marks_map[unit_id] = []
                    marks_map[unit_id].append(val)

    clear_screen()
    print_header(f"Оценки: {selected_period['name']}")
    
    table = Table(box=box.ROUNDED, show_lines=True)
    table.add_column("Предмет", style="bold white")
    table.add_column("Средний", justify="center", style="bold yellow")
    table.add_column("Оценки", style="white")
    table.add_column("Итог", justify="center", style="bold red")
    
    for unit in units_list:
        name = unit.get('unitName')
        unit_id = unit.get('unitId')
        over_mark = unit.get('overMark')
        avg_str = str(over_mark) if over_mark is not None and over_mark > 0 else "-"
        total = unit.get('totalMark', '') or "-"
        current_marks = marks_map.get(unit_id, [])
        marks_str = " ".join(current_marks)

        avg_style = "white"
        if over_mark:
            try:
                if float(over_mark) >= 4.5: avg_style = "green"
                elif float(over_mark) < 3: avg_style = "red"
            except: pass

        table.add_row(
            name, 
            Text(avg_str, style=avg_style), 
            Text(marks_str, style="cyan"), 
            Text(str(total), style="bold magenta" if total != '-' else "dim")
        )
        
    console.print(table)
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_homework():
    clear_screen()
    print_header("Домашнее задание")
    
    options = select_period_option()
    if not options:
        Prompt.ask("Enter для возврата")
        return

    table = Table(title="Выберите период для загрузки ДЗ", box=box.SIMPLE)
    table.add_column("#", style="cyan")
    table.add_column("Название", style="white")
    table.add_column("Даты", style="green")
    
    period_map = {}
    current_option_idx = None
    now = time.time() * 1000
    for idx, opt in enumerate(options, 1):
        period_map[idx] = opt
        p = opt['period']
        name = p['name']
        prefix = "  " * p.get('depth', 0)
        if p.get('is_root'):
            display_name = f"[bold blue]{p.get('group_name')}[/bold blue]: {name}"
        else:
            display_name = prefix + name
        
        if p['date1'] <= now <= p['date2']:
             if not p.get('is_root'):
                display_name = f"{prefix}{name} (Текущий)"
                current_option_idx = str(idx)

        table.add_row(str(idx), display_name, f"{p['date1Str']} - {p['date2Str']}")
    console.print(table)
    
    default_val = current_option_idx if current_option_idx else "1"
    choice = Prompt.ask("Выберите номер", default=default_val)
    if not choice.isdigit() or int(choice) not in period_map: return
    
    selected_opt = period_map[int(choice)]
    selected_period = selected_opt['period']
    
    with console.status("Загрузка домашнего задания...", spinner="dots"):
        diary_data = api.get_prs_diary(selected_period['date1'], selected_period['date2'])
        lessons = diary_data.get('lesson', [])
    
    clear_screen()
    print_header(f"ДЗ: {selected_period['name']}")
    
    hw_table = Table(box=box.ROUNDED, show_lines=True)
    hw_table.add_column("Дата", style="cyan", width=12)
    hw_table.add_column("Предмет", style="bold white", width=20)
    hw_table.add_column("Задание", style="white")
    hw_table.add_column("Файлы", style="blue")

    has_hw = False
    lessons.sort(key=lambda x: x.get('date', 0))

    for lesson in lessons:
        date_ts = lesson.get('date')
        date_str = datetime.fromtimestamp(date_ts / 1000).strftime('%d.%m.%Y')
        subject = lesson.get('unit', {}).get('name', 'Неизвестно')
        
        parts = lesson.get('part', [])
        for part in parts:
            if part.get('cat') == 'DZ':
                variants = part.get('variant', [])
                for variant in variants:
                    text_html = variant.get('text', '')
                    clean_text = clean_html(text_html)
                    
                    files = variant.get('file', [])
                    file_names = "\n".join([f.get('fileName') for f in files])
                    
                    if clean_text or file_names:
                        hw_table.add_row(date_str, subject, clean_text, file_names)
                        has_hw = True

    if has_hw:
        console.print(hw_table)
    else:
        console.print(Panel("Домашних заданий за этот период не найдено", style="yellow"))

    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_pupil_units():
    clear_screen()
    print_header("Предметы")
    
    if not api.prs_id:
        api.get_state()
    
    year_id = None
    try:
        profile = api.get_profile_new(api.prs_id)
        pupils = profile.get('pupil', [])
        if pupils:
            pupils_sorted = sorted(pupils, key=lambda x: x.get('bvt', ''), reverse=True)
            year_id = str(pupils_sorted[0].get('yearId', ''))
    except:
        pass
    
    if not year_id or not year_id.isdigit():
        year_id = Prompt.ask("[bold cyan]Введите ID учебного года[/bold cyan] (например, 88749)", default="88749")
        if not year_id or not year_id.isdigit():
            console.print("[red]Неверный ID года[/red]")
            Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
            return
    
    with console.status("Загрузка предметов...", spinner="dots"):
        try:
            result = api.get_pupil_units(api.prs_id, int(year_id))
            units = result.get('result', [])
            
            if not units:
                console.print(Panel("Предметы не найдены", style="yellow"))
                Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
                return
            
            table = Table(box=box.ROUNDED, show_lines=True)
            table.add_column("ID", justify="right", style="cyan", width=8)
            table.add_column("Предмет", style="bold white")
            table.add_column("Короткое название", style="dim")
            table.add_column("Тип", style="yellow")
            
            for unit in units:
                unit_id = unit.get('unitId', '')
                name = unit.get('name', 'Неизвестно')
                short_name = unit.get('shortName', '')
                is_odod = unit.get('isOdod', 0)
                odod_type = "ВУД" if is_odod == 2 else "Обычный" if is_odod == 0 else f"Тип {is_odod}"
                
                table.add_row(str(unit_id), name, short_name, odod_type)
            
            console.print(table)
        except Exception as e:
            console.print(f"[red]Ошибка: {e}[/red]")
    
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_homework_new():
    clear_screen()
    print_header("Домашние задания (новый формат)")
    
    if not api.prs_id:
        api.get_state()
    
    year_id = None
    try:
        profile = api.get_profile_new(api.prs_id)
        pupils = profile.get('pupil', [])
        if pupils:
            pupils_sorted = sorted(pupils, key=lambda x: x.get('bvt', ''), reverse=True)
            year_id = str(pupils_sorted[0].get('yearId', ''))
    except:
        pass
    
    if not year_id or not year_id.isdigit():
        year_id = Prompt.ask("[bold cyan]Введите ID учебного года[/bold cyan]", default="88749")
        if not year_id or not year_id.isdigit():
            console.print("[red]Неверный ID года[/red]")
            Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
            return
    
    console.print("\n[yellow]Введите период для загрузки заданий:[/yellow]")
    try:
        end_date = datetime.now()
        beg_date = end_date - timedelta(days=90)
        beg_timestamp = int(beg_date.timestamp() * 1000)
        end_timestamp = int(end_date.timestamp() * 1000)
    except:
        beg_timestamp = 1764363600000
        end_timestamp = 1788123600000
    
    with console.status("Загрузка домашних заданий...", spinner="dots"):
        try:
            result = api.get_lpart_list_pupil(
                beg_timestamp, 
                end_timestamp, 
                0,
                api.prs_id, 
                int(year_id)
            )
            
            tasks = result.get('result', [])
            
            if not tasks:
                console.print(Panel("Задания не найдены", style="yellow"))
                Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
                return
            
            tasks.sort(key=lambda x: x.get('passDt', 0), reverse=True)
            
            table = Table(box=box.ROUNDED, show_lines=True)
            table.add_column("Дата", style="cyan", width=12)
            table.add_column("Предмет", style="bold white", width=18)
            table.add_column("Задание", style="white")
            table.add_column("Статус", style="yellow", width=12)
            table.add_column("Файлы", justify="center", style="blue", width=6)
            
            for task in tasks:
                pass_dt = task.get('passDt', 0)
                if pass_dt:
                    date_str = datetime.fromtimestamp(pass_dt / 1000).strftime('%d.%m.%Y')
                else:
                    date_str = "-"
                
                unit_name = task.get('unitName', 'Неизвестно')
                preview = task.get('preview', '')[:80] + "..." if len(task.get('preview', '')) > 80 else task.get('preview', '')
                attach_cnt = task.get('attachCnt', 0)
                is_done = task.get('isDone', 0)
                is_verified = task.get('isVerified', 0)
                
                status = "✓ Выполнено" if is_done else "⏳ В работе"
                if is_verified:
                    status += " ✓"
                
                files_str = f"📎 {attach_cnt}" if attach_cnt > 0 else "-"
                
                table.add_row(date_str, unit_name, preview, status, files_str)
            
            console.print(table)
        except Exception as e:
            console.print(f"[red]Ошибка: {e}[/red]")
    
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_profile_extended():
    clear_screen()
    print_header("Расширенный профиль")
    
    if not api.prs_id:
        api.get_state()
    
    with console.status("Загрузка профиля...", spinner="dots"):
        try:
            profile = api.get_profile_new(api.prs_id)
            
            data = profile.get('data', {})
            fio = profile.get('fio', 'Неизвестно')
            birth_date = profile.get('birthDate', 'Неизвестно')
            login = profile.get('login', 'Неизвестно')
            
            main_table = Table(show_header=False, box=box.ROUNDED)
            main_table.add_column("Параметр", style="bold cyan")
            main_table.add_column("Значение", style="white")
            
            main_table.add_row("ФИО", fio)
            main_table.add_row("Логин", login)
            main_table.add_row("Дата рождения", birth_date)
            main_table.add_row("ID", str(data.get('prsId', 'Неизвестно')))
            main_table.add_row("Пол", "Мужской" if data.get('gender') == 1 else "Женский")
            
            console.print(main_table)
            
            pupils = profile.get('pupil', [])
            if pupils:
                console.print("\n[bold cyan]Учебные годы:[/bold cyan]")
                pupil_table = Table(box=box.ROUNDED, show_lines=True)
                pupil_table.add_column("Учебный год", style="bold white")
                pupil_table.add_column("Класс", style="cyan")
                pupil_table.add_column("Период", style="green")
                pupil_table.add_column("Статус", style="yellow")
                
                for pupil in pupils:
                    edu_year = pupil.get('eduYear', '')
                    class_name = pupil.get('className', '')
                    bvt = pupil.get('bvt', '')
                    evt = pupil.get('evt', '')
                    is_ready = "✓ Готов" if pupil.get('isReady') == 1 else "⚠ Не готов"
                    
                    period = f"{bvt} - {evt}"
                    pupil_table.add_row(edu_year, class_name, period, is_ready)
                
                console.print(pupil_table)
            
            prs_rel = profile.get('prsRel', [])
            if prs_rel:
                console.print("\n[bold cyan]Связи:[/bold cyan]")
                rel_table = Table(box=box.ROUNDED)
                rel_table.add_column("Роль", style="bold white")
                rel_table.add_column("ФИО", style="cyan")
                rel_table.add_column("Телефон", style="green")
                rel_table.add_column("Email", style="blue")
                
                for rel in prs_rel:
                    rel_name = rel.get('relName', '')
                    rel_data = rel.get('data', {})
                    rel_fio = f"{rel_data.get('lastName', '')} {rel_data.get('firstName', '')} {rel_data.get('middleName', '')}"
                    phone = rel_data.get('mobilePhone', rel_data.get('homePhone', '-'))
                    email = rel_data.get('email', '-')
                    
                    rel_table.add_row(rel_name, rel_fio, phone, email)
                
                console.print(rel_table)
            
        except Exception as e:
            console.print(f"[red]Ошибка: {e}[/red]")
    
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def show_user_search():
    clear_screen()
    print_header("Поиск пользователей")
    
    year_id = Prompt.ask("[bold cyan]Введите ID учебного года[/bold cyan]", default="88749")
    if not year_id.isdigit():
        console.print("[red]Неверный ID года[/red]")
        Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
        return
    
    with console.status("Поиск пользователей...", spinner="dots"):
        try:
            users = api.get_user_list_search(int(year_id))
            
            if not users:
                console.print(Panel("Пользователи не найдены", style="yellow"))
                Prompt.ask("\nНажмите Enter, чтобы вернуться назад")
                return
            
            students = [u for u in users if u.get('isStudent') == 1]
            teachers = [u for u in users if u.get('isEmp') == 1]
            parents = [u for u in users if u.get('isParent') == 1]
            
            console.print(f"\n[bold cyan]Найдено:[/bold cyan]")
            console.print(f"  👨‍🎓 Учеников: {len(students)}")
            console.print(f"  👨‍🏫 Преподавателей: {len(teachers)}")
            console.print(f"  👨‍👩‍👧 Родителей: {len(parents)}")
            
            if students:
                console.print("\n[bold cyan]Ученики (первые 20):[/bold cyan]")
                student_table = Table(box=box.ROUNDED, show_lines=True)
                student_table.add_column("ID", justify="right", style="cyan", width=8)
                student_table.add_column("ФИО", style="bold white")
                student_table.add_column("Класс", style="green")
                
                for student in students[:20]:
                    prs_id = student.get('prsId', '')
                    fio = student.get('fio', 'Неизвестно')
                    group_name = student.get('groupName', '-')
                    student_table.add_row(str(prs_id), fio, group_name)
                
                console.print(student_table)
        
        except Exception as e:
            console.print(f"[red]Ошибка: {e}[/red]")
    
    Prompt.ask("\nНажмите Enter, чтобы вернуться назад")

def open_chat_with_user(user_data):
    prs_id = user_data.get('prsId')
    fio = user_data.get('fio')
    
    if not prs_id:
        console.print("[red]Ошибка: нет ID пользователя[/red]")
        return
        
    clear_screen()
    print_header(f"Чат с {fio}")
    
    with console.status(f"Открытие чата с {fio}...", spinner="dots"):
        try:
            thread_data = api.save_thread(prs_id)
            if isinstance(thread_data, int) or (isinstance(thread_data, str) and thread_data.isdigit()):
                thread_id = int(thread_data)
                view_thread(thread_id)
            else:
                console.print(f"[red]Не удалось получить ID чата. Ответ: {thread_data}[/red]")
                Prompt.ask("Нажмите Enter")
        except Exception as e:
            console.print(f"[red]Ошибка при открытии чата: {e}[/red]")
            Prompt.ask("Нажмите Enter")


def show_school_tree():
    current_level_data = None
    path_history = []
    
    with console.status("Загрузка структуры школы...", spinner="dots"):
        try:
            tree_data = api.get_groups_tree()
            current_level_data = tree_data
        except Exception as e:
            console.print(f"[red]Ошибка загрузки справочника: {e}[/red]")
            Prompt.ask("Нажмите Enter")
            return

    while True:
        clear_screen()
        path_names = [p.get('groupName', 'Root') or p.get('groupTypeName', 'Root') or p.get('orgName', 'Root') for p in path_history]
        title = " / ".join(path_names) if path_names else "Справочник школы"
        print_header(title)

        items = []
        
        if isinstance(current_level_data, list):
            items = current_level_data
        elif isinstance(current_level_data, dict):
            if 'groups' in current_level_data:
                items.extend(current_level_data['groups'])
            if 'users' in current_level_data:
                items.extend(current_level_data['users'])
        
        if not items:
            console.print("[yellow]В этой категории пусто.[/yellow]")
        
        table = Table(box=box.SIMPLE, show_lines=True)
        table.add_column("#", style="cyan", width=4)
        table.add_column("Тип", style="dim", width=10)
        table.add_column("Название / ФИО", style="bold white")
        
        item_map = {}
        idx = 1
        
        for item in items:
            item_map[idx] = item
            
            type_str = ""
            name_str = ""
            
            if 'orgName' in item:
                type_str = "🏢 Орг."
                name_str = item['orgName']
            elif 'groupTypeName' in item and 'groupName' not in item: 
                 type_str = "📂 Кат."
                 name_str = item['groupTypeName']
            elif 'groupName' in item:
                type_str = "👥 Группа"
                name_str = item['groupName']
            elif 'fio' in item:
                type_str = "👤 Польз."
                name_str = item['fio']
                if 'pos' in item and item['pos']:
                    pos_names = [p.get('posTypeName', '') for p in item['pos']]
                    name_str += f" [dim]({', '.join(filter(None, pos_names))})[/dim]"
            
            table.add_row(str(idx), type_str, name_str)
            idx += 1
            
        console.print(table)
        console.print("\n[dim]Введите номер для перехода, 'b' назад, '0' выход в меню[/dim]")
        
        choice = Prompt.ask("Выбор")
        
        if choice == '0':
            break
        elif choice.lower() == 'b':
            if path_history:
                path_history.pop()
                if not path_history:
                    current_level_data = tree_data
                else:
                    current_level_data = path_history[-1]
            else:
                break
        elif choice.isdigit() and int(choice) in item_map:
            selected_item = item_map[int(choice)]
            
            if 'fio' in selected_item:
                action = Prompt.ask(
                    f"\nДействия с [bold cyan]{selected_item['fio']}[/bold cyan]:\n"
                    "1. Написать сообщение\n"
                    "0. Отмена\n"
                    "Выбор",
                    choices=["1", "0"]
                )
                if action == "1":
                    open_chat_with_user(selected_item)
            else:
                path_history.append(selected_item)
                current_level_data = selected_item


def main_menu():
    while True:
        clear_screen()
        print_header()
        
        user_fio = "Пользователь"
        if api.profile_data:
            user_fio = f"{api.profile_data.get('firstName')} {api.profile_data.get('lastName')}"
            
        console.print(f"[italic cyan]Добро пожаловать, {user_fio}![/italic cyan]\n", justify="center")

        menu_table = Table.grid(padding=1)
        menu_table.add_column()
        menu_table.add_row("[bold cyan]1.[/bold cyan] 📚 Дневник (Оценки)")
        menu_table.add_row("[bold cyan]2.[/bold cyan] 💬 Сообщения")
        menu_table.add_row("[bold cyan]3.[/bold cyan] 👤 Профиль")
        menu_table.add_row("[bold cyan]4.[/bold cyan] 🏠 Домашнее задание")
        menu_table.add_row("[bold cyan]5.[/bold cyan] 📖 Предметы")
        menu_table.add_row("[bold cyan]6.[/bold cyan] 📝 ДЗ (новый формат)")
        menu_table.add_row("[bold cyan]7.[/bold cyan] 👥 Поиск пользователей")
        menu_table.add_row("[bold cyan]8.[/bold cyan] 📋 Расширенный профиль")
        menu_table.add_row("[bold cyan]9.[/bold cyan] 🏫 Структура школы (Справочник)")
        menu_table.add_row("[bold cyan]0.[/bold cyan] 🚪 Выход")
        
        panel = Panel(menu_table, title="Меню", border_style="blue", padding=(1, 2))
        console.print(panel, justify="center")
        
        choice = Prompt.ask("\nВаш выбор", choices=["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        
        if choice == "1": show_diary()
        elif choice == "2": show_chats()
        elif choice == "3": show_profile()
        elif choice == "4": show_homework()
        elif choice == "5": show_pupil_units()
        elif choice == "6": show_homework_new()
        elif choice == "7": show_user_search()
        elif choice == "8": show_profile_extended()
        elif choice == "9": show_school_tree()
        elif choice == "0":
            if Confirm.ask("Вы уверены, что хотите выйти?"):
                console.print("[yellow]До свидания![/yellow]")
                break

def run():
    try:
        while True:
            if login_screen():
                main_menu()
                break 
            else:
                if not Confirm.ask("Попробовать снова?"): break
    except KeyboardInterrupt:
        console.print("\n[yellow]Принудительное завершение работы.[/yellow]")
        sys.exit(0)

if __name__ == "__main__":
    run()

from flask import Flask, flash, jsonify, render_template, redirect, url_for, request, session
from web3 import Web3
from datetime import datetime

import json

app = Flask(__name__)
app.secret_key = 'your_secret_key'

# Подключение к Infura
infura_url = "https://polygon-mainnet.infura.io/v3/e4a2683e32074103bdd80bf8abf139c2"
web3 = Web3(Web3.HTTPProvider(infura_url))
# Адрес и ABI смарт-контракта
contract_address = "0x2a0E8e208A7c8C2921CCcFD5f4B339c1953C9197"

with open('static/VotingABI.json', 'r') as abi_file:
    contract_abi = json.load(abi_file)
contract = web3.eth.contract(address=contract_address, abi=contract_abi)
admins = contract.functions.getAdmins().call()


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/voting', methods=['GET'])
def voting():
    if 'currentAccount' in session:
        votes = get_votes()
        current_account_lower = session['currentAccount'].lower()
        admins_lower = [admin.lower() for admin in admins]
        flag = current_account_lower in admins_lower
        return render_template('voting.html', votes=votes, admin=flag)
    else:
        return redirect(url_for('index'))


@app.route('/admin', methods=['GET', 'POST'])
def admin():
    current_account_lower = session['currentAccount'].lower()
    admins_lower = [admin.lower() for admin in admins]
    if current_account_lower not in admins_lower:
        return redirect(url_for('voting'))
    if request.method == 'POST':
        question = request.form['question']
        options = request.form.getlist('options')
        duration = int(request.form['duration'])
        min_votes = int(request.form['min_votes'])

        # Проверяем, подключен ли MetaMask
        if len(web3.eth.accounts) == 0:
            flash('MetaMask account not connected.', 'error')
            return redirect(url_for('create_vote'))

        try:
            tx_hash = contract.functions.createVote(question, options, duration, min_votes).transact({
                'from': web3.eth.accounts[0],
                'gas': 3000000
            })

            web3.eth.waitForTransactionReceipt(tx_hash)

            flash('Vote created successfully.', 'success')
            return redirect(url_for('voting'))

        except Exception as e:
            flash(f'Failed to create vote: {str(e)}', 'error')
            return redirect(url_for('create_vote'))

    return render_template('create_vote.html')


@app.route('/login', methods=['POST'])
def login():
    data = request.json
    if 'currentAccount' in data:
        current_account = data['currentAccount']
        session['currentAccount'] = current_account
        print(f'Received MetaMask account: {current_account}')
        return jsonify({'message': 'MetaMask account logged in successfully'}), 200
    else:
        return jsonify({'message': 'No MetaMask account provided'}), 400


def get_votes():
    votes = []
    # Получаем количество голосований
    num_votes = contract.functions.getVotesLength().call()

    for vote_id in range(num_votes-1, -1, -1):
        vote_details = contract.functions.getVoteDetails(vote_id).call()

        # Размер массива вариантов ответов
        num_options = len(vote_details[1])

        # Создаем список голосов за каждый вариант ответа
        vote_counts = vote_details[5]

        options = []
        for i in range(num_options):
            option = {
                'option': vote_details[1][i],
                'votes': vote_counts[i]
            }
            options.append(option)

        vote = {
            "id": vote_id,
            'question': vote_details[0],
            # Теперь options содержит варианты и количество голосов за каждый вариант
            'options': options,
            'endTime': vote_details[2],
            'minVotes': vote_details[3],
            'isEnded': vote_details[4]
        }
        votes.append(vote)
    print(votes)
    return votes


@app.template_filter('timestamp_to_string')
def timestamp_to_string(timestamp):
    return datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')


@app.template_filter('get_total_votes')
def get_total_votes(vote):
    total_votes = sum(option['votes'] for option in vote['options'])
    if total_votes >= vote['minVotes']:
        winner_index = max(
            range(len(vote['options'])), key=lambda i: vote['options'][i]['votes'])
        winner = vote['options'][winner_index]['option']
        return f"Вариант: {winner}<br>Число голосов: {total_votes}"
    else:
        return f"Суммарно набрано голосов: {total_votes} (Меньше чем минимум для валидного результата)"


@app.template_filter('countdown_to_string')
def countdown_to_string(timestamp):
    now = datetime.now()
    end_time = datetime.fromtimestamp(timestamp)
    delta = end_time - now

    if delta.total_seconds() <= 0:
        return 'Голосование завершено'

    days = delta.days
    hours, remainder = divmod(delta.seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    return f'{days} дней {hours} часов {minutes} минут {seconds} секунд'


if __name__ == '__main__':
    app.run(debug=True)

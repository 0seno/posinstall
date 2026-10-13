#!/bin/bash

## Variáveis
help="pinstall - Script de pós-instalação que instala pacotes baseado em um lista predefinda, e \
 configura o sistema utilizando arquivos de um repositório remoto.

usage: pinstall [OPÇÕES]

Opções:
-h|--help Exibe a mensagem de ajuda e sai
-l|--list <installed|missing|all> Apenas exibe quais pacotes da lista estão instalados, faltando ou ambos.
-f|--file <ARQUIVO> Define um arquivo contendo a lista de pacotes (um pacote por linha).
-y|--yes Desabilita modo interativo, instalando os pacotes da lista que não estão presentes no sistema,\
 sem perguntar.
-s|--skip Pula a instalação de pacotes (Estágio 1).
-u|--user <GIT_USER> Define o nome do usuário do GitHub."

n_argumentos="$#"
arquivo_lista="$HOME/lista-pacotes" # trocar para $HOME/.config/posinstall/
opcoes="(-h|--help|-s|--skip|-l|--list|-f|--file|-u|--user|-y|--yes)"

declare -a instalados
declare -a nao_instalados
declare -a erro

erro[1]="O arquivo que contém a lista de pacotes não existe ou não é legível."
erro[2]="A instalação não pôde ser concluída."
erro[3]="A lista de pacotes não deve ser uma lista vazia."
erro[4]="Opções/argumentos inválidos."
erro[5]="Necessita especificar um arquivo contendo a lista de pacotes"
erro[6]="Erro ao clonar o repositório git"
erro[7]="Erro na criação do diretório de backup"
erro[8]="Erro ao mover $HOME/$j para o diretório de backup"
erro[9]="Erro ao mover $HOME/$j/$k para o diretório de backup"
erro[10]="Erro na criação dos links do dotfiles"

f_pacotes=
f_skip=
f_installed=
f_n_installed=
f_exit=
f_yes=

verde="\033[32m"
vermelho="\033[31m"
color_reset="\033[0m"

# Regex de borda
# Borda início
bi='(^|[[:space:]])'
# Borda fim
bf='([[:space:]]|$)'

## Funções

help_usage() { echo "$help"; }

sair() {
    echo "erro: ${erro[$1]}"
    exit $1
}

# Lê a primeira palavra de cada linha de arquivo_lista, testa se o pacote está ou não instalado,
# populando os arrays instalados e/ou nao_instalados
testar_pacotes() {
    # Testa se o arquivo é legível
    [[ -r "$arquivo_lista" ]] || { help_usage; sair 1; }
    # Testa se a lista de pacotes está vazia
    [[ -s "$arquivo_lista" ]] || { help_usage; sair 3; }
    while read -r pacote _; do
        dpkg-query --show -f '${binary:Package}\n' "$pacote" &>/dev/null \
	    && instalados+=("$pacote") \
	    || nao_instalados+=("$pacote")
    done <"$arquivo_lista"
} 2>/dev/null

exibir_instalados() {
    for i in "${instalados[@]}"; do
        echo -e "$i ${verde}- Instalado${color_reset}"
    done
}

exibir_n_instalados() {
    for i in "${nao_instalados[@]}"; do
        echo -e "$i ${vermelho}- Não instalado${color_reset}"
    done
}

instalar_pacotes() {
    echo -e "\nInstalando pacotes..."
    if [[ "$(id -u)" -eq 0 ]]; then
        { apt update && apt install -y "${nao_instalados[@]}"; } || sair 2
    else
        { sudo apt update && sudo apt install -y "${nao_instalados[@]}"; } || sair 2
    fi
}

# Testa opções
testar_argumentos() {
    for ((i=1; i<="$n_argumentos"; i++)); do
	# Argumento
	argumento="${@:i:1}"
	# Argumento anterior
	anterior="${@:$((i-1)):1}"
	# Argumento posterior
	posterior="${@:$((i+1)):1}"
	# Testa opções -h e --help, se sucesso, utiliza a função de ajuda
	if [[ "$argumento" =~ $bi(-h|--help)$bf ]]; then
	    help_usage
	    exit 0
	# Testa opções -s e --skip, se sucesso, define f_skip='true'
	elif [[ "$argumento" =~ $bi(-s|--skip)$bf ]]; then
	    f_skip='true'
	# Testa opções -f e --file, se sucesso, define arquivo_lista com o arquivo especificado
	elif [[ "$argumento" =~ $bi(-f|--file)$bf ]]; then
	    arquivo_lista="$posterior"
	    f_pacotes='true'
	# Testa se o argumento é o arquivo_lista e se é precedido pelas opções -f ou --file
	elif [[ "$argumento" == "$arquivo_lista" ]]; then
	    ! [[ "$anterior" =~ $bi(-f|--file)$bf ]] && { help_usage; sair 4; }
	    true
	# Testa as opções -l e --list, se sucesso, testa se essas opções possuem ou não argumentos
	elif [[ "$argumento" =~ $bi(-l|--list)$bf ]]; then
	    if [[ -z "$posterior" ]] \
		|| [[ "$posterior" =~ $bi(-h|--help|-s|--skip|-f|--file|-u|--user|-y|--yes)$bf ]]; then
		f_installed='true'
		f_n_installed='true'
	    elif [[ "$posterior" == "all" ]]; then
		f_installed='true'
		f_n_installed='true'
	    elif [[ "$posterior" == "installed" ]]; then
		f_installed='true'
	    elif [[ "$posterior" == "missing" ]]; then
		f_n_installed='true'
	    # Chama a função de ajuda e sai com erro caso haja algum argumento não esperado
	    else
		help_usage
		sair 4
	    fi
	    # Habilita a flag para chamar a função de testar pacotes
	    f_pacotes='true'
	    # Habilita a flag para sair com sucesso
	    f_exit='true'
	# Testa os argumentos das opções -l e --list
	elif [[ "$argumento" =~ $bi(all|installed|missing)$bf ]]; then
	    ! [[ "$anterior" =~ $bi(-l|--list)$bf ]] && sair 4
	    true
	# Testa as opções -y e --yes
	elif [[ "$argumento" =~ $bi(-y|--yes)$bf ]]; then
	    f_pacotes='true'
	    f_yes='true'
	# Testa opções -u e --user
	elif [[ "$argumento" =~ $bi(-u|--user)$bf ]]; then
	    [[ -z "$posterior" ]] && sair 4 
	    [[ "$posterior" =~ $bi$opcoes$bf ]] && sair 4
	    [[ "$posterior" == "$arquivo_lista" ]] && sair 4 
	    git_user="$posterior"
	    # Testa se há somente a opção -u/--user e seu argumento
	    if [[ "$n_argumentos" -eq 2 ]]; then
		f_pacotes='true'
		f_installed='true'
		f_n_installed='true'
	    fi
	# Tratamento do argumento de -u|--user
	elif [[ ! "$argumento" =~ $bi$opcoes$bf ]] && [[ "$anterior" =~ $bi(-u|--user)$bf ]]; then
	    true
	# Chama a função de ajuda e sai com erro caso haja alguma opção não esperada
	else
	    help_usage
	    sair 4
	fi
    done
}

## Main

if [[ "$n_argumentos" -eq 0 ]]; then
    f_pacotes='true'
    f_installed='true'
    f_n_installed='true'
else
    testar_argumentos "$@"
fi

# Estágio 1
# (Ignorado se f_skip=true)
if [[ -z $f_skip ]]; then
    [[ -n $f_installed || -n "$f_n_installed" ]] && echo -e "Estágio 1: Listando pacotes...\n"
    [[ -n "$f_pacotes" ]] && testar_pacotes 
    [[ -n "$f_installed" ]] && exibir_instalados
    [[ -n "$f_n_installed" ]] && exibir_n_instalados
    [[ -n "$f_exit" ]] && exit 0
    # Testa se será interativo
    if [[ -z $f_yes ]]; then
	while true; do
	    read -p "Deseja instalar os pacotes não instalados?[S/n] " opt
	    case $opt in
		s|S|y|Y|'')
		    instalar_pacotes
		    break
		    ;;
		n|N)
		    echo "Os pacotes não serão instalados. Abortando..."
		    break
		    ;;
		*)
		    true
		    ;;
	    esac
	done
    else
	instalar_pacotes
    fi
else
    echo -e "\nPulando Estágio 1"
fi

# Estágio 2
echo -e "\nEstágio 2: Configurando dotfiles...\n"
while [[ -z "$git_user" ]]; do
    read -rp "Usuário git: " git_user
done
cd $HOME && { git clone https://github.com/$git_user/dotfiles.git || sair 6; }
backup_dir="$HOME/.posinstall/backup_dotfiles_$(date +%d-%m-%Y_%H:%M:%S)"
mkdir -p $backup_dir || sair 8
# Habilita a expansão de arquivos ocultos por shell globbing
shopt -s dotglob
cd $HOME/dotfiles
# Loop para expandir e interagir com cada arquivo/subdiretório de dotfiles/
for i in *; do
    if [[ -d $i ]] && [[  $i != ".git" ]]; then
	cd $i
	# Loop para expandir e interagir com cada arquivo/subdiretório de cada subdiretório de dotfiles/ (dotfiles/$i/)
	for j in *; do
	    if [[ -f "$HOME/$j" ]] && [[ ! -L "$HOME/$j" ]]; then
		mv $HOME/$j $backup_dir || sair 8
	    elif [[ -d "$HOME/$j" ]] && [[ ! -L "$HOME/$j" ]] && [[ "$HOME/$j" != "$HOME/.config" ]]; then
		mv $HOME/$j $backup_dir || sair 8
	    elif [[ -d "$HOME/$j" ]] && [[ ! -L "$HOME/$j" ]] && [[ "$HOME/$j" == "$HOME/.config" ]]; then
		cd $j
		# Loop para expandir e interagir com cada arquivo/subdiretório de dotfiles/$i/.config
		for k in *; do
			[[ -d "$HOME/$j/$k" ]] && [[ ! -L "$HOME/$j/$k" ]] && { mv $HOME/$j/$k $backup_dir || sair 9; }
			[[ -f "$HOME/$j/$k" ]] && [[ ! -L "$HOME/$j/$k" ]] && { mv $HOME/$j/$k $backup_dir || sair 9; }
		done
		cd ../
	    fi
	done
	cd $HOME/dotfiles
    fi
done
# Desabilita a expandsão de arquivos ocultos por shell globbing
shopt -u dotglob
echo -e "\n+++ OS DOTFILES ORIGINAIS FORAM MOVIDOS PARA $backup_dir +++\n"
# Utiliza gnu-stow para a criação os links de dotfiles
stow * && echo "Links de dotfiles criados com sucesso!" || sair 10 

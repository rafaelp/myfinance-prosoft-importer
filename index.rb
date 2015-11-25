#!/usr/bin/env ruby

require 'ap'
require 'thor'
require 'qif'
require 'date'
require 'rest_client'
require 'pry'
require 'xmlsimple'

class MyfinanceImporter < Thor
  desc "import -f [FILE]", "Imports XML [FILE] to MyFinance"
  method_option :xml, :aliases => "-f", :desc => "Specify a filename of xml exported from ProSoft"
  def import
    check_myfinance_variables
    check_file_exists
    read_xml
    create_qif
    upload
  end

  private
    def check_myfinance_variables
      return if myfinance_available?
      puts "    #{'ATENÇÃO!!!'.red} #{'As variáveis de ambiente com as informações do MyFinance não estão setadas.'.white}"
      puts "    Pegue seu Token de acesso à API em https://app.passaporteweb.com.br/two_factor/".white
      puts "    Para configurar, utilize o comando abaixo, substituindo os valores de cada variável.".white
      puts "    $ export MYFINANCE_ACCOUNT_ID=99 MYFINANCE_ENTITY=99 MYFINANCE_DEPOSIT_ACCOUNT=99 MYFINANCE_TOKEN=SEUTOKENAQUI".blue
      puts "    A importação não foi realizada :(".red
      exit
    end

    def check_file_exists
      puts "--> Lendo o arquivo #{xml_filename}...".yellow
      return if File.exists?(xml_filename)
      puts "    Arquivo não encontrado.".red
      exit
    end

    def read_xml
      puts "--> Validando formato...".yellow
      begin
        @doc = XmlSimple.xml_in(xml_filename, { 'KeyAttr' => 'FieldName' })
      rescue Nokogiri::XML::SyntaxError => e
        puts "    Arquivo mal formatado: #{e}".red
        exit
      end
    end

    def foreach_item
      @fields_keys = {
        '{MovDiário.Emissão}' => :emissao,
        '{MovDiário.Saldo}' => :saldo,
        '{MovDiário.Valor Crd}' => :credito,
        '{MovDiário.Valor Deb}' => :debito,
        '{MovDiário.Operação}' => :operacao,
        '{MovDiário.Tipo}' => :tipo,
        '{MovDiário.Documento}' => :documento,
        '{MovDiário.Histórico}' => :historico,
        '{MovDiário.Lançamento}' => :lancamento,
        '{MovDiário.Terceiro}' => :terceiro,
        '{MovDiário.Conciliado}' => :conciliado,
        '{MovDiário.Atualizado}' => :atualizado,
      }
      @doc['FormattedAreaPair'][0]['FormattedAreaPair'][0]['FormattedAreaPair'].each do |item|
        @row = {}
        fields = item['FormattedArea'][0]['FormattedSections'][0]['FormattedSection'][0]['FormattedReportObjects'][0]['FormattedReportObject']
        fields.each_pair do |field_key, field_value|
          @row[@fields_keys[field_key]] = field_value['Value'][0]
        end
        yield @row
      end
    end

    def create_qif
      puts "--> Criando o arquivo no formato QIF...".yellow
      Qif::Writer.open(qif_filename, type = 'Bank', format = 'dd/mm/yyyy') do |qif|
        @total = 0
        foreach_item do |item|
          date = Date.strptime(item[:emissao], "%Y-%m-%d")
          transaction = {
            date: date,
            memo: item[:historico],
            number: item[:documento],
            amount: item[:operacao] == 'C' ? item[:credito].to_f : item[:debito].to_f ,
          }
          @first_transaction_date ||= date
          @last_transaction_date = date
          @total = @total + 1
          qif << Qif::Transaction.new(transaction)
        end
        puts "    O arquivo contém #{@total} transações do dia #{@first_transaction_date} ao dia #{@last_transaction_date}.".white
      end
    end

    def upload
      puts "--> Importando o arquivo para o MyFinance...".yellow
      RestClient.post "https://#{ENV['MYFINANCE_TOKEN']}:X@app.myfinance.com.br/entities/#{ENV['MYFINANCE_ENTITY']}/deposit_accounts/#{ENV['MYFINANCE_DEPOSIT_ACCOUNT']}/bank_statements", {'bank_statement[file]' => File.new(qif_filename, 'r'), :multipart => true}, {'ACCOUNT_ID' => ENV['MYFINANCE_ACCOUNT_ID']}
      puts "    O arquivo #{qif_filename} foi enviado para o MyFinance com sucesso!".green
      puts "--> Excluindo o arquivo #{qif_filename}...".yellow
      delete_qif_file
      puts "    Arquivo excluído com sucesso!".green
    rescue
      puts "    Houve um erro ao enviar o arquivo para o MyFinance :(".red
    end

    def delete_qif_file
      FileUtils.rm(qif_filename)
    end

    def qif_filename
      xml_filename.gsub(".xml", ".qif")
    end

    def xml_filename
      @xml_filename ||= options[:xml]
    end

    def myfinance_available?
      ENV['MYFINANCE_TOKEN'] and ENV['MYFINANCE_ENTITY'] and ENV['MYFINANCE_DEPOSIT_ACCOUNT'] and ENV['MYFINANCE_ACCOUNT_ID']
    end

end

MyfinanceImporter.start(ARGV)
# frozen_string_literal: true

module Burrow
  module Server
    class Room
      attr_reader :code, :members, :config, :match, :match_id, :messages, :name, :created_at, :password_hash
      attr_accessor :host_id, :updated_at, :saved_result

      def initialize(code:, host:, name:, config: {}, password: "")
        @code, @name, @host_id = code, Protocol.name(name), host[:id]
        @config = Config.new(config)
        raise RuleError, "Room password is too long." unless password.is_a?(String) && password.bytesize <= 128
        @password_hash = password.empty? ? nil : Digest::SHA256.hexdigest(code + password)
        @members = [member(host)]
        @messages, @match = [], nil
        @created_at = @updated_at = Time.now.to_i
        @saved_result = false
      end

      def stage = match ? (match.finished? ? "finished" : "playing") : "lobby"
      def full? = members.length >= 6
      def host?(id) = host_id == id
      def member(session) = {id: session[:id], name: session[:name], bot: false, ready: false, connected: true}
      def human_ids = members.reject { |m| m[:bot] }.map { |m| m[:id] }

      def join(session, password)
        raise RuleError, "Room password is too long." unless password.is_a?(String) && password.bytesize <= 128
        raise RuleError, "This match has already started." unless stage == "lobby"
        raise RuleError, "This room already has six teams." if full?
        raise RuleError, "You are already in this room." if members.any? { |m| m[:id] == session[:id] }
        candidate = Digest::SHA256.hexdigest(code + password.to_s)
        raise RuleError, "The room password is incorrect." if password_hash && !OpenSSL.fixed_length_secure_compare(password_hash, candidate)
        members << member(session)
        touch
      end

      def command(id, type, values)
        case type
        when "ready"
          require_lobby
          person = members.find { |m| m[:id] == id }
          raise RuleError, "Join the room first." unless person
          person[:ready] = values["ready"] == true
        when "configure"
          require_host(id)
          require_lobby
          @config = Config.new(values.fetch("config"))
          members.each { |m| m[:ready] = m[:bot] }
        when "add_bot"
          require_host(id)
          require_lobby
          raise RuleError, "This room already has six teams." if full?
          color = members.length
          members << {id: "bot-#{SecureRandom.hex(4)}", name: TEAM_NAMES[color], bot: true, ready: true, connected: true}
        when "kick"
          require_host(id)
          require_lobby
          target = members.find { |m| m[:id] == values["player"] }
          raise RuleError, "Choose another team to remove." unless target && target[:id] != id
          members.delete(target)
          return target[:id]
        when "start"
          require_host(id)
          require_lobby
          raise RuleError, "Invite a friend or add a computer team." unless members.length >= 2
          raise RuleError, "Every player must be connected and ready." unless members.all? { |m| m[:connected] && (m[:ready] || m[:id] == host_id) }
          @match = Match.new(players: members, config: config)
          @match_id = SecureRandom.hex(12)
        when "rematch"
          require_host(id)
          raise RuleError, "Finish the current match first." unless stage == "finished"
          @match = nil
          @match_id = nil
          @saved_result = false
          members.each { |m| m[:ready] = m[:bot] }
        when "chat"
          text = values["text"]
          raise RuleError, "Messages need 1–180 printable characters." unless text.is_a?(String) && text.valid_encoding? && text.strip.length.between?(1, 180) && !text.match?(/[[:cntrl:]]/)
          author = members.find { |m| m[:id] == id }
          messages << {name: author[:name], text: text.strip, time: Time.now.to_i}
          messages.shift while messages.length > 40
        when "surrender"
          raise RuleError, "There is no active match." unless match && !match.finished?
          match.surrender(id)
        else
          raise RuleError, "Start a match first." unless match
          match.command(id, type, values)
        end
        touch
        nil
      end

      def leave(id)
        match&.surrender(id) unless match&.finished?
        members.reject! { |m| m[:id] == id }
        choose_host if host_id == id
        touch
      end

      def connected(id, online)
        person = members.find { |m| m[:id] == id }
        return unless person
        person[:connected] = online
        person[:ready] = false unless online || person[:bot]
        choose_host if !online && host_id == id
        touch
      end

      def summary = {code: code, name: name, stage: stage, count: members.length, locked: !!password_hash, biome: config["biome"], host: members.find { |m| m[:id] == host_id }&.fetch(:name)}
      def snapshot = summary.merge(host_id: host_id, match_id: match_id, members: members, config: config.to_h, messages: messages)

      def checkpoint
        {"code" => code, "name" => name, "host_id" => host_id, "members" => members,
          "config" => config.to_h, "password_hash" => password_hash, "messages" => messages,
          "created_at" => created_at, "updated_at" => updated_at, "saved_result" => saved_result,
          "match" => match&.checkpoint, "match_id" => match_id}
      end

      def self.restore(value)
        room = allocate
        %w[code name host_id password_hash created_at updated_at saved_result match_id].each { |key| room.instance_variable_set("@#{key}", value[key]) }
        room.instance_variable_set(:@match_id, SecureRandom.hex(12)) if value["match"] && !value["match_id"]
        room.instance_variable_set(:@config, Config.new(value.fetch("config")))
        room.instance_variable_set(:@members, value.fetch("members").map { |m| m.transform_keys(&:to_sym).merge(connected: !!m["bot"]) })
        room.instance_variable_set(:@messages, value.fetch("messages").map { |m| m.transform_keys(&:to_sym) })
        room.instance_variable_set(:@match, value["match"] && Match.restore(value["match"]))
        room
      end

      private

      def require_lobby = (raise RuleError, "These rules are locked while a match is running." unless stage == "lobby")
      def require_host(id) = (raise RuleError, "Only the room host can do that." unless host?(id))
      def touch = (@updated_at = Time.now.to_i)
      def choose_host
        candidate = members.find { |m| !m[:bot] && m[:connected] } || members.find { |m| !m[:bot] }
        @host_id = candidate&.fetch(:id)
      end
    end
  end
end

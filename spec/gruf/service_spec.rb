# coding: utf-8
# Copyright (c) 2017-present, BigCommerce Pty. Ltd. All rights reserved
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
require 'spec_helper'
require 'securerandom'

describe Gruf::Service do
  let(:endpoint) { ThingService.new }
  let(:id) { 1 }
  let(:req) { ::Rpc::GetThingRequest.new(id: id) }
  let(:resp) { ::Rpc::GetThingResponse.new(id: id) }
  let(:call_signature) { :get_thing }
  let(:metadata) { {} }
  let(:active_call) { double(:active_call, output_metadata: {}, metadata: metadata)}

  describe 'functional test' do
    let(:client) { TestClient.new }

    context 'for a request/response call' do
      let(:id) { 1 }
      subject { client.get_thing(id: id) }

      it 'should return the thing', run_thing_server: true do
        client = build_client
        resp = client.call(:GetThing, id: 1)
        expect(resp.message).to be_a(Rpc::GetThingResponse)
        expect(resp.message.thing).to be_a(Rpc::Thing)
        expect(resp.message.thing.id).to eq id
      end
    end
    #
    context 'for a server streaming call' do
      it 'should return the things in a stream from the server', run_thing_server: true do
        client = build_client
        resp = client.call(:GetThings)
        resp.message.each do |r|
          expect(r).to be_a(Rpc::Thing)
        end
      end
    end

    # context 'for a bidi streaming call' do
    #   it 'should return the things from the server', run_thing_server: true do
    #     things = []
    #     5.times do
    #       things << Rpc::Thing.new(
    #         id: rand(1..1000).to_i,
    #         name: FFaker::Lorem.word.to_s
    #       )
    #     end
    #
    #     client = build_client
    #     client.call(:CreateThingsInStream, things.enum_for) do |r|
    #       puts "Received response: #{r.inspect}"
    #     end
    #   end
    # end
    #
    # context 'for a client streaming call' do
    #   xit 'should return the things from the server', run_thing_server: true do
    #     things = []
    #     5.times do
    #       things << Rpc::Thing.new(
    #           id: rand(1..1000).to_i,
    #           name: FFaker::Lorem.word.to_s
    #       )
    #     end
    #
    #     client = build_client
    #     resp = client.call(:CreateThings, things: things)
    #     expect(resp.message).to be_a(Rpc::CreateThingsResponse)
    #     expect(resp.message.things.first).to be_a(Rpc::Thing)
    #   end
    # end
  end

  describe 'exceptions' do
    context 'failing with a NotFound error' do
      subject { endpoint.get_fail(req, active_call) }
      let(:error) { Gruf::Error.new(code: :not_found, app_code: :thing_not_found, message: "#{req.id} not found!") }

      it 'should raise a GRPC::NotFound error' do
        expect do
          subject
        end.to raise_error do |err|
          expect(err).to be_a(GRPC::NotFound)
          expect(err.code).to eq 5
          expect(err.message).to eq "5:#{id} not found!"
          expect(err.metadata).to eq(foo: 'bar', :'error-internal-bin' => error.serialize)
        end
      end
    end

    context 'on an uncaught exception' do
      subject { endpoint.get_uncaught_exception(req, active_call) }
      let(:base_error_message) { Gruf.internal_error_message }
      let(:error_message) { 'epic fail' }
      let(:error) { Gruf::Error.new(code: :internal, app_code: :unknown, message: error_message) }

      it 'by default should raise a GRPC::Internal error using the exception message' do
        expect do
          subject
        end.to raise_error do |err|
          expect(err).to be_a(GRPC::Internal)
          expect(err.code).to eq 13
          expect(err.message).to eq "13:#{error_message}"
          expect(err.metadata).to eq(:'error-internal-bin' => error.serialize)
        end
      end

      it 'should attach a backtrace if configured to do so' do
        Gruf.backtrace_on_error = true
        expect do
          subject
        end.to raise_error do |err|
          parsed_error = JSON.parse(err.metadata[:'error-internal-bin'])
          expect(parsed_error['debug_info']).to_not be_empty
          expect(parsed_error['debug_info']['stack_trace']).to_not be_empty
        end
      end

      context 'when we override the base exception message' do
        let(:message) { SecureRandom.hex }

        before do
          Gruf.configure do |c|
            c.use_exception_message = false
            c.internal_error_message = message
          end
        end

        it 'should raise a GRPC::Internal error with the correct message' do
          expect do
            subject
          end.to raise_error do |err|
            expect(err).to be_a(GRPC::Internal)
            expect(err.code).to eq 13
            expect(err.message).to eq "13:#{message}"
          end
        end
      end

      context 'when we enable the internal exception message config' do
        before do
          Gruf.configure do |c|
            c.use_exception_message = false
          end
        end

        it 'should raise a GRPC::Internal error and use e.message' do
          expect do
            subject
          end.to raise_error do |err|
            expect(err).to be_a(GRPC::Internal)
            expect(err.code).to eq 13
            expect(err.message).to eq "13:#{Gruf.internal_error_message}"
          end
        end
      end
    end

    context 'on a success' do
      subject { endpoint.get_thing(req, active_call) }

      it 'should return normally' do
        expect(subject).to be_a(Rpc::GetThingResponse)
      end
    end
  end

  describe '.method_added' do
    it 'should add wrapper method for endpoint' do
      expect(endpoint.respond_to?(:get_thing_with_intercept)).to be_truthy
      expect(endpoint.respond_to?(:get_thing_without_intercept)).to be_truthy
    end

    it 'should not add wrapper method for non-endpoints' do
      expect(endpoint.respond_to?(:not_a_endpoint_with_intercept)).to_not be_truthy
      expect(endpoint.respond_to?(:not_a_endpoint_without_intercept)).to_not be_truthy
    end
  end

  describe '.authenticate' do
    subject { endpoint.get_thing(req, active_call) }

    it 'should be called for every method call' do
      expect(endpoint).to receive(:authenticate).once
      expect(subject).to be_a(Rpc::GetThingResponse)
    end

    context 'when the authentication fails' do
      before do
        allow(Gruf::Authentication).to receive(:verify).and_return(false)
      end

      it 'should call fail! and return a GRPC::Unauthenticated response' do
        expect {
          subject
        }.to raise_error(GRPC::Unauthenticated) { |e|
          expect(e.code).to eq GRPC::Core::StatusCodes::UNAUTHENTICATED
        }
      end
    end
  end

  describe '.fail!' do
    let(:error) { endpoint.send(:error) }
    let(:error_code) { :not_found }
    let(:app_code) { :thing_not_found }
    let(:message) { 'Thing 1 not found!' }

    subject { endpoint.fail!(req, active_call, error_code, app_code, message, metadata) }

    it 'should call fail! on the error and set the appropriate values' do
      expect(error).to receive(:fail!).with(active_call)
      subject
      expect(error.code).to eq error_code
      expect(error.app_code).to eq app_code
      expect(error.message).to eq message
      expect(error.metadata).to eq metadata
    end
  end

  describe '.has_field_errors?' do
    let(:error) { endpoint.send(:error) }
    subject { endpoint.send(:has_field_errors?) }

    context 'when there are field errors' do
      before do
        endpoint.send(:add_field_error, :name, :invalid, 'Invalid name')
      end

      it 'should return true' do
        expect(subject).to be_truthy
      end
    end

    context 'when there are no field errors' do
      it 'should return false' do
        expect(subject).to be_falsey
      end
    end
  end

  describe '.set_debug_info' do
    let(:detail) { FFaker::Lorem.sentence }
    let(:stack_trace) { FFaker::Lorem.sentences(2) }
    let(:error) { endpoint.send(:error) }

    subject { endpoint.send(:set_debug_info, detail, stack_trace) }

    it 'should pass through to the error call' do
      expect(error).to receive(:set_debug_info).with(detail, stack_trace)
      subject
    end
  end

  describe '.error' do
    subject { endpoint.send(:error) }
    it 'should return a Gruf::Error object' do
      expect(subject).to be_a(Gruf::Error)
    end
  end
end

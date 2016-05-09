class RecurringInvoice < Common
  # Relations
  has_many :invoices

  # Validation
  validates :series, presence: true
  validates :name, presence: true
  validates :starting_date, presence: true, if: :status?
  validates :period, :period_type, presence: true, if: :status?
  validate :valid_date_range

  PERIOD_TYPES = [
    ["Daily", "days"],
    ["Monthly", "months"],
    ["Yearly", "years"]
  ].freeze

  # Status
  INACTIVE = 0
  ACTIVE = 1

  STATUS = {inactive: INACTIVE, active: ACTIVE}

  def to_s
    "#{name}"
  end
  # returns all recurring_invoices with specified status
  scope :with_status, -> (status) {where status: status}

  def get_status
    if status
      STATUS[status]
    else
      # For nil case
      STATUS[:inactive]
    end
  end

  def generate_pending_invoices
    if !status?
      return
    end
    # how many invoices are generated by now
    occurrences = Invoice.belonging_to(id).count
    # max occurrences of invoices
    max = max_occurrences.nil? ? 99999 : max_occurrences
    # finishing date
    ending_date = finishing_date.blank? ? Date.new(2999) : finishing_date
    # next date to issue an invoice
    next_date = self.invoices.length > 0 ? \
        self.invoices.last.created_at + period.send(period_type) \
        : starting_date
    invs = []

    while next_date <= [Date.today, ending_date].min and occurrences < max do
      inv = self.becomes(Invoice).deep_clone include: [:items]
      inv.recurring_invoice_id = self.id
      inv.status = 'Open'
      inv.issue_date = Date.today
      inv.due_date = Date.today + days_to_due.days if days_to_due
      if self.sent_by_email  # If recurring is set to send emails
        inv.send_email
      end
      inv.save
      next_date += period.send period_type
      occurrences += 1
      invs.append inv
    end
    save
    invs
  end

  def self.with_pending_invoices
    # candidates to have pending invoices
    candidates = with_status(1).where("period is not null").
      where(period_type: ['days', 'months', 'years'])
    pendings = []
    candidates.each do |actual|

      # get the finishing date from either max_occurrences or finishing_date
      ending_date = Date.new 2999
      if actual.max_occurrences?
        if Invoice.belonging_to(actual.id).count >= actual.max_occurrences
          next
        end
        ending_date = actual.starting_date +
          (actual.period * actual.max_occurrences).send(actual.period_type)
      end
      if actual.finishing_date? and actual.finishing_date < ending_date
        ending_date = actual.finishing_date
      end

      # get the next invoice issuing date
      next_date = actual.invoices.length > 0 ? \
          actual.invoices.last.created_at + actual.period.send(actual.period_type) \
          : actual.starting_date

      # is it within range?
      if next_date > Date.today or !next_date.in? (actual.starting_date...ending_date)
        next
      end

      pendings.append actual
    end
  end

  private

  def valid_date_range
    return if starting_date.blank? || finishing_date.blank?

    if starting_date > finishing_date
      errors.add(:finishing_time, "Finishing Date must be after Starting Date")
    end
  end

end

import Cocoa

class PickerViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var cancelButton: NSButton!
    @IBOutlet weak var doneButton: NSButton!
    
    var values: [String] = []
    var selectedValue: String = ""
    weak var delegate: PickerViewDelegate?
    
    static func instantiate(values: [String], selectedValue: String, delegate: PickerViewDelegate) -> PickerViewController {
        let vc = PickerViewController(nibName: "PickerViewController", bundle: nil)
        vc.values = values
        vc.selectedValue = selectedValue
        vc.delegate = delegate
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
        
        if let index = values.firstIndex(of: selectedValue) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            tableView.scrollRowToVisible(index)
        }
    }
    
    @IBAction func cancelButtonClicked(_ sender: Any) {
        dismiss(nil)
    }
    
    @IBAction func doneButtonClicked(_ sender: Any) {
        if let selectedRow = tableView.selectedRow, selectedRow >= 0, selectedRow < values.count {
            delegate?.didSelectValue(value: values[selectedRow])
        }
        dismiss(nil)
    }
}

extension PickerViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return values.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("PickerCell"), owner: self) as? NSTableCellView
        cell?.textField?.stringValue = values[row]
        return cell
    }
} 